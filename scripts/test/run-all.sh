#!/usr/bin/env sh
# run-all.sh — run every scripts/test/test-*.sh fixture suite.
#
# WHY this exists: CI runs this one script, so a new suite can't be added and
# silently never run (scripts/test/test-ci-wiring.sh checks the workflow calls it).
# The two scan suites (test-ci-checks.sh, test-pre-commit.sh) run a second time with
# SH=bash: they run the scripts under "$SH", and bash drops set -e inside $( ) where
# dash (Ubuntu's sh) keeps it (starter T-024).
#
# Run:  sh scripts/test/run-all.sh
# Exit: 0 every suite passed, 1 any suite failed or none was found.

set -u

test_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd) || exit 1
root=$(CDPATH='' cd -- "$test_dir/../.." && pwd) || exit 1
cd "$root" || exit 1

count=0
failed=0
summary=''

# run_suite <label> <path> [bash]: run one suite (with SH=bash if asked), print its
# PASS/FAIL line and keep it for the summary.
run_suite() {
  count=$((count + 1))
  rc=0
  if [ "${3:-}" = bash ]; then SH=bash sh "$2" || rc=$?
  else sh "$2" || rc=$?; fi
  if [ "$rc" -eq 0 ]; then line="PASS: $1"
  else line="FAIL: $1 (exit $rc)"; failed=1; fi
  printf '%s\n\n' "$line"
  summary="$summary$line
"
}

for suite in "$test_dir"/test-*.sh; do
  [ -f "$suite" ] || continue
  name=${suite##*/}
  run_suite "$name" "$suite"
  case "$name" in
    test-ci-checks.sh|test-pre-commit.sh) run_suite "$name (bash)" "$suite" bash ;;
  esac
done

echo "run-all.sh summary"
printf '%s' "$summary"
if [ "$count" -eq 0 ]; then
  echo "FAIL: no scripts/test/test-*.sh suite found" >&2
  exit 1
fi
[ "$failed" -eq 0 ]
