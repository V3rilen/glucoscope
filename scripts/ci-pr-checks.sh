#!/usr/bin/env sh
# ci-pr-checks.sh — run the TARGET branch's procedure gates against a PR head.
#
# WHY this exists: a PR build checks out the PR, so its scripts/ci-checks.sh and
# .placeholder-allow were written by the PR's author. Running those lets a PR
# loosen the rules it is judged by (edit a regex, allowlist its own placeholder)
# with no visible CI change (starter T-014). This extracts both from the branch the PR
# merges into and runs that copy; the PR is read only as data, through git.
#
# The pipeline takes THIS script from the target branch too (the "trusted-gate"
# block in .github/workflows/checks.yml); the PR's own copy runs only while the
# target has none (bootstrap), with a warning. What stays PR-controlled is the
# pipeline YAML itself: review any PR that changes it before merging.
#
# Bootstrap (T-005): a target that has NEVER had either gate script (none now, none
# in its history) has no trusted copy, so the PR head's own committed gate judges
# the PR, with a warning: the pull request that adds the starter to an existing
# project. That is safe only because the workflow block above already runs the
# PR's own runner in that state (the trusted-gate block in .github/workflows/checks.yml);
# a change to that block must keep it so.
#
# Usage:  sh scripts/ci-pr-checks.sh <target-ref> <head-sha>
#   <target-ref>  tip of the branch the PR merges into (ci-checks.sh diffs from
#                 the merge base, so the tip is the right base)
#   <head-sha>    the PR commit being validated (may be a synthetic merge)
# Run from the repository root: an older ci-checks.sh reads ./.placeholder-allow.
# Exit:   ci-checks.sh's exit code; 1 if the gate (the target's, or on bootstrap
#         the PR head's) can't be loaded.

set -u
LC_ALL=C; export LC_ALL

die() { printf 'CI-PR-CHECK FAIL: %s Failing closed: the gates were not run.\n' "$*" >&2; exit 1; }
# warn: a CI-native warning annotation, so it shows on a green build too.
warn() {
  if [ -n "${GITHUB_ACTIONS:-}" ]; then printf '::warning::%s\n' "$*"
  else printf 'CI-PR-CHECK WARN: %s\n' "$*" >&2; fi
}

target_arg="${1:-}" head_arg="${2:-}"
{ [ -n "$target_arg" ] && [ -n "$head_arg" ]; } || die "Usage: ci-pr-checks.sh <target-ref> <head-sha>."
case "$target_arg" in -*) die "Target '$target_arg' does not resolve to a commit (looks like an option)." ;; esac
case "$head_arg" in -*) die "Head '$head_arg' does not resolve to a commit (looks like an option)." ;; esac
target=$(git rev-parse --verify --quiet "$target_arg^{commit}") \
  || die "Target '$target_arg' does not resolve to a commit."
head=$(git rev-parse --verify --quiet "$head_arg^{commit}") \
  || die "Head '$head_arg' does not resolve to a commit."

tmp=$(mktemp -d 2>/dev/null || mktemp -d -t cipr) || die "mktemp failed."
cleanup() { rc=$?; rm -rf "$tmp"; exit "$rc"; }   # keep the exit code
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# bootstrap: the target has no scripts/ci-checks.sh. Refuse unless it has never had
# either gate script, then run the PR head's committed gate (never the working tree).
# Every message is fixed text plus resolved hex SHAs. Ends the script.
bootstrap() {
  rentry=$(git ls-tree --full-tree "$target" -- scripts/ci-pr-checks.sh) \
    || die "git ls-tree $target failed."
  [ -z "$rentry" ] \
    || die "Target $target has no scripts/ci-checks.sh. Land scripts/ on the target branch before requiring this check."
  shallow=$(git rev-parse --is-shallow-repository) \
    || die "git rev-parse --is-shallow-repository failed."
  [ "$shallow" = false ] \
    || die "This is a shallow clone, so the target's history cannot be checked. Fetch full history (actions/checkout fetch-depth: 0) and re-run."
  had=$(git log -1 --full-history --format=%H "$target" -- ':(top)scripts/ci-checks.sh' ':(top)scripts/ci-pr-checks.sh') \
    || die "git log $target failed."
  [ -z "$had" ] \
    || die "Target $target has had scripts/ci-checks.sh or scripts/ci-pr-checks.sh in its history (commit $had) but has neither now, so this pull request is not judged by its own gate. If this pull request adds or restores the starter's scripts/, read it yourself and merge it: until the check is required on the target, a red check does not block the merge, and every later pull request is judged by the gate it adds. Otherwise restore scripts/ on the target branch first."

  warn "Bootstrap: the target branch has never had the gate, so this pull request is judged by its own copy of scripts/ci-checks.sh and .placeholder-allow. This is expected once, on the pull request that adds the starter; read that pull request yourself, because the gate that passed it came from it. Every later pull request is judged by the target branch's copy. If this appears on any other pull request, do not merge it."

  hentry=$(git ls-tree --full-tree "$head" -- scripts/ci-checks.sh) \
    || die "git ls-tree $head failed."
  case "$hentry" in
    '') die "PR head $head has no scripts/ci-checks.sh, so there is no gate to run." ;;
    '100644 blob '*|'100755 blob '*) ;;
    *) die "PR head's scripts/ci-checks.sh is not a regular file." ;;
  esac
  git cat-file blob "$head:scripts/ci-checks.sh" > "$tmp/ci-checks.sh" \
    || die "Reading the PR head's scripts/ci-checks.sh failed."
  hentry=$(git ls-tree --full-tree "$head" -- .placeholder-allow) \
    || die "git ls-tree $head failed."
  case "$hentry" in
    '') : > "$tmp/placeholder-allow" ;;
    '100644 blob '*|'100755 blob '*)
      git cat-file blob "$head:.placeholder-allow" > "$tmp/placeholder-allow" \
        || die "Reading the PR head's .placeholder-allow failed." ;;
    *) die "PR head's .placeholder-allow is not a regular file." ;;
  esac
  CI_PLACEHOLDER_ALLOW="$tmp/placeholder-allow" sh "$tmp/ci-checks.sh" "$target" "$head"
  exit $?
}

# The target's gate script must be a regular file. ls-tree prints nothing when the
# path is absent and fails on a git error, so "missing" and "broken" stay apart.
entry=$(git ls-tree --full-tree "$target" -- scripts/ci-checks.sh) \
  || die "git ls-tree $target failed."
case "$entry" in
  '') bootstrap ;;
  '100644 blob '*|'100755 blob '*) ;;
  *) die "Target's scripts/ci-checks.sh is not a regular file." ;;
esac
git cat-file blob "$target:scripts/ci-checks.sh" > "$tmp/ci-checks.sh" \
  || die "Reading the target's scripts/ci-checks.sh failed."

# Absent allowlist on the target means nothing is allowlisted: an empty file, never
# a fallback to the PR's own .placeholder-allow.
entry=$(git ls-tree --full-tree "$target" -- .placeholder-allow) \
  || die "git ls-tree $target failed."
case "$entry" in
  '') : > "$tmp/placeholder-allow" ;;
  '100644 blob '*|'100755 blob '*)
    git cat-file blob "$target:.placeholder-allow" > "$tmp/placeholder-allow" \
      || die "Reading the target's .placeholder-allow failed." ;;
  *) die "Target's .placeholder-allow is not a regular file." ;;
esac

if ! grep -q CI_PLACEHOLDER_ALLOW "$tmp/ci-checks.sh"; then
  warn "The target's ci-checks.sh predates starter T-014: it reads this PR's own .placeholder-allow and doesn't diff with --text, so .gitattributes or a NUL byte can hide content from it."
fi

CI_PLACEHOLDER_ALLOW="$tmp/placeholder-allow" sh "$tmp/ci-checks.sh" "$target" "$head"
