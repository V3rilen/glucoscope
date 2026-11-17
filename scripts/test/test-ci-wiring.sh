#!/usr/bin/env sh
# Every fixture suite runs in CI (starter T-015): the GitHub workflow runs
# scripts/test/run-all.sh, which runs each scripts/test/test-*.sh, so a new suite
# can't be added and silently never run. A commented-out step doesn't count.
# The workflow pins a shellcheck version and checksum and uses both in its download
# (starter T-021). Starter T-022 adds: one pinned Ubuntu image; a least-privilege
# GitHub workflow (actions pinned by SHA, no ${{ }} in run: scripts); and the
# local shellcheck steps in .githooks/README.md match the CI pin. Starter T-024 adds: the
# safe-echo block is byte-identical in scripts/ci-checks.sh and .githooks/pre-commit;
# neither prints a raw file name or subject; every se_safe call checks its status; the
# scan decisions read content only (cut -f2-); every git diff/show pins its output
# shape; and run-all.sh runs the two scan suites under bash as well.
#
# Run:  sh scripts/test/test-ci-wiring.sh
#       CI_WIRING_ROOT=<dir> sh scripts/test/test-ci-wiring.sh   (check another tree)
# Exit: 0 all pass, 1 any failure.

set -u
LC_ALL=C; export LC_ALL

test_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
root="${CI_WIRING_ROOT:-$(CDPATH='' cd -- "$test_dir/../.." && pwd)}"

tmp=$(mktemp -d 2>/dev/null || mktemp -d -t cw)
trap 'rm -rf "$tmp"' EXIT

pass=0
fail=0
ok()  { pass=$((pass + 1)); printf "  PASS: %s\n" "$1"; }
bad() { fail=$((fail + 1)); printf "  FAIL: %s\n" "$1" >&2; }

ci_file=.github/workflows/checks.yml

# check_runall <root>: the workflow has a step running scripts/test/run-all.sh.
check_runall() {
  r=$1
  [ -f "$r/$ci_file" ] || { echo "FAIL: no CI file found"; return 0; }
  [ -f "$r/scripts/test/run-all.sh" ] || echo "FAIL: scripts/test/run-all.sh is missing"
  # A step line: "run: sh scripts/test/run-all.sh" ("- run:" counts too).
  awk -v s="scripts/test/run-all.sh" '
    { line = $0; sub(/^[ \t]*-?[ \t]*/, "", line) }
    line == "run: sh " s { found = 1 }
    END { exit !found }' "$r/$ci_file" || echo "FAIL: scripts/test/run-all.sh is not a step in $ci_file"
}

# check_pins <root>: one "FAIL: ..." line per shellcheck pin problem in the CI file.
check_pins() {
  r=$1
  [ -f "$r/$ci_file" ] || { echo "FAIL: no CI file found"; return 0; }
  for c in $ci_file; do
    for k in SHELLCHECK_VERSION SHELLCHECK_SHA256; do
      n=$(grep -c "^[[:space:]]*$k:" "$r/$c")
      [ "$n" -eq 1 ] || echo "FAIL: $c sets $k $n times, not once"
    done
    h=$(sed -n 's/^[[:space:]]*SHELLCHECK_SHA256:[[:space:]]*//p' "$r/$c" | head -n 1)
    case "$h" in
      *[!0-9a-f]*|'') echo "FAIL: $c's SHELLCHECK_SHA256 is not a sha256 hex digest" ;;
      *) [ "${#h}" -eq 64 ] || echo "FAIL: $c's SHELLCHECK_SHA256 is not a sha256 hex digest" ;;
    esac
    # shellcheck disable=SC2016  # the ${...} is the CI file's text, not ours
    grep -qF 'releases/download/${SHELLCHECK_VERSION}/' "$r/$c" \
      || echo "FAIL: $c doesn't download the pinned SHELLCHECK_VERSION"
    # shellcheck disable=SC2016
    grep -q '"${SHELLCHECK_SHA256}  .*" | sha256sum -c' "$r/$c" \
      || echo "FAIL: $c doesn't check the download against SHELLCHECK_SHA256"
    # ...and a mismatch must stop the job: the next line's handler exits 1.
    awk '/sha256sum -c/ { getline nxt; if (nxt ~ /\|\| \{.*exit 1/) ok = 1 } END { exit !ok }' "$r/$c" \
      || echo "FAIL: $c doesn't fail the job on a checksum mismatch"
  done
}

# check_images <root>: every uncommented runs-on: is the same pinned image.
check_images() {
  r=$1 all=''
  for c in $ci_file; do
    [ -f "$r/$c" ] || continue
    imgs=$(sed -nE 's/^[[:space:]]*(runs-on):[[:space:]]*([^[:space:]#]+).*/\2/p' "$r/$c")
    [ -n "$imgs" ] || echo "FAIL: $c names no runner image"
    for i in $imgs; do
      case "$i" in *-latest) echo "FAIL: $c uses the floating image $i" ;; esac
      all="$all
$i"
    done
  done
  n=$(printf '%s\n' "$all" | grep -v '^$' | sort -u | wc -l | tr -d ' ')
  [ "$n" -le 1 ] || echo "FAIL: the CI file uses $n different images:$(printf '%s\n' "$all" | grep -v '^$' | sort -u | tr '\n' ' ')"
}

# check_gh_privs <root>: the GitHub workflow runs with least privilege.
check_gh_privs() {
  c=$ci_file
  [ -f "$1/$c" ] || return 0
  f="$1/$c"
  grep -qx 'permissions: {}' "$f" || echo "FAIL: $c has no top-level 'permissions: {}'"
  grep -n ': write' "$f" | grep -v '^[0-9]*:[[:space:]]*#' | sed "s|^|FAIL: $c grants write access: |"
  awk -v c="$c" '
    function report() {
      if (!perm) print "FAIL: " c " job " job " lacks permissions: contents: read"
      if (!to) print "FAIL: " c " job " job " has no timeout-minutes"
    }
    /^jobs:/ { injobs = 1; next }
    injobs && /^  [A-Za-z0-9_-]+:[[:space:]]*$/ { if (job != "") report(); job = $1; sub(/:$/, "", job); perm = 0; to = 0; next }
    job != "" && /^    permissions:/ { getline nxt; if (nxt ~ /^      contents: read[[:space:]]*$/) perm = 1 }
    job != "" && /^    timeout-minutes:/ { to = 1 }
    END { if (job != "") report() }' "$f"
  n_co=$(grep -c 'uses: actions/checkout@' "$f"); n_pc=$(grep -c 'persist-credentials: false' "$f")
  [ "$n_co" -eq "$n_pc" ] || echo "FAIL: $c has $n_co checkout steps but $n_pc with persist-credentials: false"
  grep -nE '^[[:space:]]*(- )?uses:' "$f" | grep -vE '@[0-9a-f]{40}([[:space:]]|$)' \
    | sed "s|^|FAIL: $c uses an action not pinned to a commit SHA: |"
  # ${{ }} inside a run: script is pasted into the shell text; values go through env:.
  awk -v c="$c" '
    /^[[:space:]]*(- )?run:/ { match($0, /^[[:space:]]*(- )?/); ind = RLENGTH; inrun = 1
      if ($0 ~ /\$\{\{/) print "FAIL: " c ":" NR " has ${{ }} in a run: script"; next }
    inrun { match($0, /^[[:space:]]*/)
      if ($0 !~ /^[[:space:]]*$/ && RLENGTH < ind) inrun = 0
      else if ($0 ~ /^[[:space:]]*-?[[:space:]]*[A-Za-z_-]+:/ && RLENGTH <= ind) inrun = 0
      else if ($0 ~ /\$\{\{/) print "FAIL: " c ":" NR " has ${{ }} in a run: script" }' "$f"
}

# check_local_pin <root>: .githooks/README.md's local shellcheck steps use the CI pin.
check_local_pin() {
  [ -f "$1/$ci_file" ] || return 0
  v=$(sed -n 's/^[[:space:]]*SHELLCHECK_VERSION:[[:space:]]*//p' "$1/$ci_file" | head -n 1)
  h=$(sed -n 's/^[[:space:]]*SHELLCHECK_SHA256:[[:space:]]*//p' "$1/$ci_file" | head -n 1)
  f="$1/.githooks/README.md"
  if [ ! -f "$f" ]; then echo "FAIL: .githooks/README.md is missing"; return 0; fi
  grep -qF "$v" "$f" || echo "FAIL: .githooks/README.md doesn't name the CI's shellcheck $v"
  grep -qF "$h" "$f" || echo "FAIL: .githooks/README.md doesn't give the CI's shellcheck checksum"
}

# --- PR-controlled text never reaches the log (starter T-024) ------------------------
se_scripts='scripts/ci-checks.sh .githooks/pre-commit'

# check_block <root>: one safe-echo block per script, byte-identical in both.
check_block() {
  for s in $se_scripts; do
    [ -f "$1/$s" ] || { echo "FAIL: $s is missing"; return 0; }
    nb=$(grep -c '^# BEGIN safe-echo' "$1/$s"); ne=$(grep -c '^# END safe-echo$' "$1/$s")
    [ "$nb" -eq 1 ] || echo "FAIL: $s has $nb BEGIN safe-echo markers, not 1"
    [ "$ne" -eq 1 ] || echo "FAIL: $s has $ne END safe-echo markers, not 1"
  done
  sed -n '/^# BEGIN safe-echo/,/^# END safe-echo$/p' "$1/scripts/ci-checks.sh" > "$tmp/blk1"
  sed -n '/^# BEGIN safe-echo/,/^# END safe-echo$/p' "$1/.githooks/pre-commit" > "$tmp/blk2"
  [ -s "$tmp/blk1" ] || echo "FAIL: scripts/ci-checks.sh has no safe-echo block"
  cmp -s "$tmp/blk1" "$tmp/blk2" || echo "FAIL: the safe-echo blocks in scripts/ci-checks.sh and .githooks/pre-commit differ"
}

# check_unsanitized <root>: no message or printf expands a raw name or subject. Comment
# lines are skipped; $sf, $f_diff and the like don't match.
check_unsanitized() {
  for s in $se_scripts; do
    [ -f "$1/$s" ] || continue
    grep -n '' "$1/$s" | grep -v '^[0-9]*:[[:space:]]*#' \
      | grep -E '(^|[[:space:];&|:])(err|fail|die|warn)[[:space:]]+"[^"]*\$\{?(f|first|hit|index_hits)([^A-Za-z0-9_]|$)' \
      | sed "s|^|FAIL: $s prints an unsanitized name: |"
    grep -n '' "$1/$s" | grep -v '^[0-9]*:[[:space:]]*#' \
      | grep -E '(printf|echo)[^|]*\$\{?(f|first|hit|index_hits)([^A-Za-z0-9_]|$)[^|]*$' \
      | sed "s|^|FAIL: $s prints an unsanitized name: |"
  done
}

# check_se_status <root>: every $(se_safe "...") is followed by ||, so a sanitizer
# failure blocks under bash too (bash drops set -e inside $( )).
check_se_status() {
  for s in $se_scripts; do
    [ -f "$1/$s" ] || continue
    grep -n 'se_safe "[^"]*")' "$1/$s" | grep -v '^[0-9]*:[[:space:]]*#' \
      | grep -vE 'se_safe "[^"]*")[[:space:]]*[|][|]' \
      | sed "s|^|FAIL: $s doesn't check se_safe's status: |"
  done
}

# check_decisions <root>: each grep -q over diff content reads a cut -f2- capture
# (content only), never the N<TAB>content or raw diff text; at least two per script.
check_decisions() {
  for s in $se_scripts; do
    [ -f "$1/$s" ] || continue
    awk -v s="$s" '
      /^[ \t]*#/ { next }
      /=[$][(]printf .*[|] cut -f2-[)]/ { v = $0; sub(/^[ \t]*/, "", v); sub(/=.*/, "", v); cut[v] = 1 }
      /printf .*[|] grep -q/ && match($0, /"[$][A-Za-z_][A-Za-z0-9_]*"/) {
        v = substr($0, RSTART + 2, RLENGTH - 3)
        if (v ~ /^(added|added_n|added_lines|f_added|f_n|f_diff|full_diff|staged_diff)$/) {
          n++; if (!(v in cut)) print "FAIL: " s ":" NR " decides on $" v ", not a cut -f2- capture"
        }
      }
      END { if (n < 2) print "FAIL: " s " has " n + 0 " decision greps on diff content, not at least 2" }' "$1/$s"
  done
}

# check_diff_flags <root>: every $(git ... diff|show ...) pins the output shape, and
# each script unsets GIT_DIFF_OPTS.
check_diff_flags() {
  for s in $se_scripts; do
    [ -f "$1/$s" ] || continue
    awk -v s="$s" '
      /^[ \t]*#/ { next }
      /[$][(]git ([^ ]+ )*(diff|show) / { n++
        if (!index($0, "-c diff.relative=false")) print "FAIL: " s ":" NR " runs git without -c diff.relative=false"
        if (!index($0, "-c diff.suppressBlankEmpty=false")) print "FAIL: " s ":" NR " runs git without -c diff.suppressBlankEmpty=false"
        if (!index($0, "--no-color")) print "FAIL: " s ":" NR " runs git without --no-color"
        if (!index($0, "--submodule=short")) print "FAIL: " s ":" NR " runs git without --submodule=short"
      }
      END { if (!n) print "FAIL: " s " runs no git diff or show" }' "$1/$s"
    grep -qx 'unset GIT_DIFF_OPTS' "$1/$s" || echo "FAIL: $s doesn't unset GIT_DIFF_OPTS"
  done
}

# check_git_quiet <root>: every git call is a $(git ... 2>/dev/null) capture. Git's own
# warnings quote a repo's .gitattributes and .gitmodules, which a PR controls.
check_git_quiet() {
  for s in $se_scripts; do
    [ -f "$1/$s" ] || continue
    awk -v s="$s" '
      /^[ \t]*#/ { next }
      { a = $0; c = gsub(/[$][(]git /, "", a); b = $0; q = gsub(/2>\/dev\/null[)]/, "", b); n += c
        if (q < c) print "FAIL: " s ":" NR " runs git without 2>/dev/null"
        if ($0 ~ /(^|[;&|])[ \t]*git /) print "FAIL: " s ":" NR " runs git outside a $( ) capture" }
      END { if (!n) print "FAIL: " s " runs no git capture" }' "$1/$s"
  done
}

# check_se_where <root>: se_where is only ever handed the sanitized name, $sf.
check_se_where() {
  for s in $se_scripts; do
    [ -f "$1/$s" ] || continue
    grep -n 'se_where' "$1/$s" | grep -v '^[0-9]*:[[:space:]]*#' | grep -v 'se_where() {' \
      | grep -v 'se_where "[$]sf"' | sed "s|^|FAIL: $s passes se_where an unsanitized path: |"
  done
}

# report <description> <check output>
report() {
  if printf '%s\n' "$2" | grep -q '^FAIL'; then
    bad "$1"; printf '%s\n' "$2" | grep '^FAIL' | sed 's/^/    /' >&2
  else ok "$1"; fi
}
# expect_fail <description> <needle> <check output>
expect_fail() {
  if printf '%s\n' "$3" | grep -qF -- "$2"; then ok "$1"
  else bad "$1 (wanted '$2'; got: $3)"; fi
}

echo "test-ci-wiring.sh"

report "the workflow runs scripts/test/run-all.sh ($root)" "$(check_runall "$root")"
report "the workflow pins shellcheck once, by checksum ($root)" "$(check_pins "$root")"
report "every job runs on the same pinned runner image ($root)" "$(check_images "$root")"
report "the GitHub workflow runs with least privilege ($root)" "$(check_gh_privs "$root")"
report "the local shellcheck steps match the CI pin ($root)" "$(check_local_pin "$root")"
report "the safe-echo block is identical in both scripts ($root)" "$(check_block "$root")"
report "no script prints a raw name or subject ($root)" "$(check_unsanitized "$root")"
report "every se_safe call checks its status ($root)" "$(check_se_status "$root")"
report "the scan decisions read content only ($root)" "$(check_decisions "$root")"
report "every git diff/show pins its output shape ($root)" "$(check_diff_flags "$root")"
report "every git call discards git's own stderr ($root)" "$(check_git_quiet "$root")"
report "se_where only gets the sanitized name ($root)" "$(check_se_where "$root")"

# --- Fixtures -------------------------------------------------------------------
fx() {
  rm -rf "$tmp/fx"; mkdir -p "$tmp/fx/scripts/test" "$tmp/fx/.github/workflows"
  printf '#!/bin/sh\n' > "$tmp/fx/scripts/test/run-all.sh"
  printf 'jobs:\n  t:\n    steps:\n      - name: a\n        run: sh scripts/test/run-all.sh\n' > "$tmp/fx/$ci_file"
}
fx; report "fixture: a workflow that runs run-all.sh passes" "$(check_runall "$tmp/fx")"
fx; printf 'jobs:\n  t:\n    steps:\n      - run: sh scripts/test/run-all.sh\n' > "$tmp/fx/$ci_file"
report "fixture: a '- run:' step counts" "$(check_runall "$tmp/fx")"
fx; printf 'jobs:\n  t:\n    steps:\n      # - run: sh scripts/test/run-all.sh\n' > "$tmp/fx/$ci_file"
expect_fail "a commented-out step doesn't count" "run-all.sh is not a step in $ci_file" "$(check_runall "$tmp/fx")"
fx; printf 'jobs:\n  t:\n    steps:\n      - run: sh scripts/test/run-all.sh.bak\n' > "$tmp/fx/$ci_file"
expect_fail "a step for a different file doesn't count" "run-all.sh is not a step in $ci_file" "$(check_runall "$tmp/fx")"
fx; rm "$tmp/fx/scripts/test/run-all.sh"
expect_fail "a missing run-all.sh is caught" "scripts/test/run-all.sh is missing" "$(check_runall "$tmp/fx")"
fx; rm "$tmp/fx/$ci_file"
expect_fail "no CI file at all is a failure, not a pass" "no CI file found" "$(check_runall "$tmp/fx")"

# --- run-all.sh fixtures: this tree's run-all.sh over stub suites -------------------
# stub <name> [<body>]: a suite that prints its name and the SH it was given.
stub() {
  # shellcheck disable=SC2016  # the ${SH...} is the stub's text
  printf '#!/bin/sh\necho "ran %s SH=${SH:-unset}"\n%s\n' "$1" "${2:-exit 0}" > "$tmp/fxr/scripts/test/$1"
}
fxr() {
  rm -rf "$tmp/fxr"; mkdir -p "$tmp/fxr/scripts/test"
  cp "$root/scripts/test/run-all.sh" "$tmp/fxr/scripts/test/run-all.sh"
  stub test-a.sh; stub test-ci-checks.sh; stub test-pre-commit.sh
  stub helper.sh   # not a suite
}
run_all() { out=$( unset SH; sh "$tmp/fxr/scripts/test/run-all.sh" 2>&1 ); rc=$?; }
has() { printf '%s\n' "$out" | grep -qxF -- "$1"; }
fxr; run_all
if [ "$rc" -eq 0 ] && has "ran test-a.sh SH=unset" && has "PASS: test-a.sh" && ! has "ran helper.sh SH=unset"
then ok "run-all.sh runs every test-*.sh and nothing else"; else bad "run-all.sh runs every test-*.sh and nothing else (rc=$rc, out: $out)"; fi
for suite in test-ci-checks.sh test-pre-commit.sh; do
  if has "ran $suite SH=unset" && has "ran $suite SH=bash" && has "PASS: $suite" && has "PASS: $suite (bash)"
  then ok "run-all.sh runs $suite again with SH=bash"; else bad "run-all.sh runs $suite again with SH=bash (out: $out)"; fi
done
if has "ran test-a.sh SH=bash"; then bad "run-all.sh runs only the two scan suites under bash (out: $out)"
else ok "run-all.sh runs only the two scan suites under bash"; fi
fxr; stub test-b.sh 'exit 3'; run_all
if [ "$rc" -ne 0 ] && has "FAIL: test-b.sh (exit 3)" && has "PASS: test-a.sh" && has "ran test-pre-commit.sh SH=unset"
then ok "a failing suite fails run-all.sh, and the later suites still run"; else bad "a failing suite fails run-all.sh, and the later suites still run (rc=$rc, out: $out)"; fi
fxr
# shellcheck disable=SC2016  # the ${SH...} is the stub's text
stub test-ci-checks.sh '[ "${SH:-}" != bash ]'; run_all
if [ "$rc" -ne 0 ] && has "PASS: test-ci-checks.sh" && has "FAIL: test-ci-checks.sh (bash) (exit 1)"
then ok "a suite that fails only under bash fails run-all.sh"; else bad "a suite that fails only under bash fails run-all.sh (rc=$rc, out: $out)"; fi
fxr; rm "$tmp/fxr/scripts/test/test-a.sh" "$tmp/fxr/scripts/test/test-ci-checks.sh" "$tmp/fxr/scripts/test/test-pre-commit.sh"; run_all
if [ "$rc" -ne 0 ]; then ok "no suites at all is a failure, not a pass"; else bad "no suites at all is a failure, not a pass (out: $out)"; fi

# --- Shellcheck pin fixtures --------------------------------------------------------
sha=$(printf 'a%.0s' 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 \
  33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50 51 52 53 54 55 56 57 58 59 60 61 62 63 64)
# pin_file <path> <version> <sha>: a CI file that pins, downloads and checks shellcheck.
pin_file() {
  # shellcheck disable=SC2016  # the ${...} is the fixture's text
  printf '  SHELLCHECK_VERSION: %s\n  SHELLCHECK_SHA256: %s\n          url="x/releases/download/${SHELLCHECK_VERSION}/y"\n          echo "${SHELLCHECK_SHA256}  $tarball" | sha256sum -c - \\\n            || { echo "mismatch"; exit 1; }\n' "$2" "$3" > "$1"
}
fxp() {
  rm -rf "$tmp/fxp"; mkdir -p "$tmp/fxp/.github/workflows"
  pin_file "$tmp/fxp/$ci_file" v1.0 "$sha"
}
fxp; report "fixture: a pinned, checked download passes" "$(check_pins "$tmp/fxp")"
fxp; pin_file "$tmp/fxp/$ci_file" v1.0 "${sha#a}"
expect_fail "a short checksum is caught" "$ci_file's SHELLCHECK_SHA256 is not a sha256 hex digest" "$(check_pins "$tmp/fxp")"
fxp; grep -v SHELLCHECK_SHA256: "$tmp/fxp/$ci_file" > "$tmp/x" && mv "$tmp/x" "$tmp/fxp/$ci_file"
expect_fail "a missing checksum pin is caught" "$ci_file sets SHELLCHECK_SHA256 0 times" "$(check_pins "$tmp/fxp")"
fxp; printf '  SHELLCHECK_VERSION: v1.1\n' >> "$tmp/fxp/$ci_file"
expect_fail "a second version pin is caught" "$ci_file sets SHELLCHECK_VERSION 2 times" "$(check_pins "$tmp/fxp")"
fxp
# shellcheck disable=SC2016  # the ${...} is the fixture's text
sed 's|${SHELLCHECK_VERSION}|v1.0|' "$tmp/fxp/$ci_file" > "$tmp/x" && mv "$tmp/x" "$tmp/fxp/$ci_file"
expect_fail "a pin the download doesn't use is caught" "$ci_file doesn't download the pinned SHELLCHECK_VERSION" "$(check_pins "$tmp/fxp")"
fxp; grep -v 'sha256sum -c' "$tmp/fxp/$ci_file" > "$tmp/x" && mv "$tmp/x" "$tmp/fxp/$ci_file"
expect_fail "a download that skips the checksum is caught" "$ci_file doesn't check the download against SHELLCHECK_SHA256" "$(check_pins "$tmp/fxp")"
fxp; sed 's/exit 1; }/true; }/' "$tmp/fxp/$ci_file" > "$tmp/x" && mv "$tmp/x" "$tmp/fxp/$ci_file"
expect_fail "a mismatch that doesn't stop the job is caught" "$ci_file doesn't fail the job on a checksum mismatch" "$(check_pins "$tmp/fxp")"

# --- Image, privilege and local-pin fixtures (starter T-022) ---------------------------
gw() {  # gw <path>: a least-privilege workflow with two jobs
  mkdir -p "$(dirname "$1")"
  cat > "$1" <<'EOF'
on: pull_request
permissions: {}
jobs:
  a:
    runs-on: ubuntu-24.04
    timeout-minutes: 5
    permissions:
      contents: read
    env:
      X: ${{ github.sha }}
      SHELLCHECK_VERSION: v1.0
      SHELLCHECK_SHA256: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    steps:
      - uses: actions/checkout@0123456789abcdef0123456789abcdef01234567 # v9
        with:
          persist-credentials: false
      - run: |
          echo "$X"
  b:
    runs-on: ubuntu-24.04
    timeout-minutes: 5
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@0123456789abcdef0123456789abcdef01234567 # v9
        with:
          persist-credentials: false
      - name: s
        run: sh x.sh
EOF
}
fxg() {
  rm -rf "$tmp/fxg"; mkdir -p "$tmp/fxg/.githooks"
  gw "$tmp/fxg/.github/workflows/checks.yml"
  printf 'Run shellcheck v1.0 (sha256 %s) locally.\n' "$sha" > "$tmp/fxg/.githooks/README.md"
}
edit_fx() {  # edit_fx <file> <sed expression>
  sed "$2" "$1" > "$tmp/x" && mv "$tmp/x" "$1"
}
first() {  # first <file> <old line text> [<new line text>]: replace (or drop) the first exact line
  awk -v o="$2" -v n="${3-}" -v drop=$# 'done != 1 && $0 == o { done = 1; if (drop == 2) next; $0 = n } { print }' \
    "$1" > "$tmp/x" && mv "$tmp/x" "$1"
}
g="$tmp/fxg/.github/workflows/checks.yml"
fxg; report "fixture: a pinned, least-privilege setup passes" "$(check_images "$tmp/fxg"; check_gh_privs "$tmp/fxg"; check_local_pin "$tmp/fxg")"
fxg; first "$g" '    runs-on: ubuntu-24.04' '    runs-on: ubuntu-latest'
expect_fail "a job on ubuntu-latest is caught" "uses the floating image ubuntu-latest" "$(check_images "$tmp/fxg")"
fxg; first "$g" '    runs-on: ubuntu-24.04' '    runs-on: ubuntu-22.04'
expect_fail "two different images are caught" "uses 2 different images" "$(check_images "$tmp/fxg")"
fxg; edit_fx "$g" '/^permissions: {}$/d'
expect_fail "a missing top-level permissions: {} is caught" "has no top-level 'permissions: {}'" "$(check_gh_privs "$tmp/fxg")"
fxg; first "$g" '      contents: read' '      contents: write'
out=$(check_gh_privs "$tmp/fxg")
expect_fail "a job with write access is caught" "grants write access" "$out"
expect_fail "...and named as lacking contents: read" "job a lacks permissions: contents: read" "$out"
fxg; first "$g" '    timeout-minutes: 5'
expect_fail "a job without timeout-minutes is caught" "job a has no timeout-minutes" "$(check_gh_privs "$tmp/fxg")"
fxg; first "$g" '          persist-credentials: false'
expect_fail "a checkout that keeps credentials is caught" "2 checkout steps but 1 with persist-credentials: false" "$(check_gh_privs "$tmp/fxg")"
fxg; first "$g" '      - uses: actions/checkout@0123456789abcdef0123456789abcdef01234567 # v9' '      - uses: actions/checkout@v4'
expect_fail "an action pinned by tag is caught" "not pinned to a commit SHA" "$(check_gh_privs "$tmp/fxg")"
fxg
# shellcheck disable=SC2016  # the ${{ }} is the fixture's text
edit_fx "$g" 's/echo "\$X"/echo "${{ github.sha }}"/'
expect_fail "\${{ }} in a run: script is caught" "has \${{ }} in a run: script" "$(check_gh_privs "$tmp/fxg")"
fxg
# shellcheck disable=SC2016  # the ${{ }} is the fixture's text
edit_fx "$g" 's/run: sh x.sh/run: sh x.sh ${{ github.sha }}/'
expect_fail "\${{ }} in a one-line run: is caught" "has \${{ }} in a run: script" "$(check_gh_privs "$tmp/fxg")"
fxg; edit_fx "$tmp/fxg/.githooks/README.md" 's/v1.0/v0.9/'
expect_fail "local steps naming another shellcheck are caught" "doesn't name the CI's shellcheck v1.0" "$(check_local_pin "$tmp/fxg")"
fxg; edit_fx "$tmp/fxg/.githooks/README.md" "s/$sha/b${sha#a}/"
expect_fail "local steps with another checksum are caught" "doesn't give the CI's shellcheck checksum" "$(check_local_pin "$tmp/fxg")"

# --- safe-echo fixtures (starter T-024) ----------------------------------------------
# fxs: copies of this tree's two scripts, so each fixture mutates the real code.
fxs() {
  rm -rf "$tmp/fxs"; mkdir -p "$tmp/fxs/scripts" "$tmp/fxs/.githooks"
  cp "$root/scripts/ci-checks.sh" "$tmp/fxs/scripts/ci-checks.sh"
  cp "$root/.githooks/pre-commit" "$tmp/fxs/.githooks/pre-commit"
}
ci="$tmp/fxs/scripts/ci-checks.sh"; pc="$tmp/fxs/.githooks/pre-commit"
fxs; report "fixture: this tree's scripts pass every safe-echo check" \
  "$(check_block "$tmp/fxs"; check_unsanitized "$tmp/fxs"; check_se_status "$tmp/fxs"; check_decisions "$tmp/fxs"; check_diff_flags "$tmp/fxs"; check_git_quiet "$tmp/fxs"; check_se_where "$tmp/fxs")"
fxs; edit_fx "$pc" 's/NR <= 20/NR <= 21/'
expect_fail "a drifted safe-echo block is caught" "safe-echo blocks in scripts/ci-checks.sh and .githooks/pre-commit differ" "$(check_block "$tmp/fxs")"
fxs; printf '# BEGIN safe-echo again\n' >> "$ci"
expect_fail "a second BEGIN marker is caught" "scripts/ci-checks.sh has 2 BEGIN safe-echo markers" "$(check_block "$tmp/fxs")"
fxs; edit_fx "$pc" '/^# END safe-echo$/d'
expect_fail "a missing END marker is caught" ".githooks/pre-commit has 0 END safe-echo markers" "$(check_block "$tmp/fxs")"
# shellcheck disable=SC2016  # the $f etc. are the fixtures' text
for line in '  err "Unreplaced placeholder in $f"' "  die \"git diff -- '\$f' failed.\"" '  fail "bad ${f}"' \
            '  warn "$index_hits is regenerated"' "  printf 'First line: %s\\n' \"\$first\""; do
  fxs; printf '%s\n' "$line" >> "$ci"
  expect_fail "an unsanitized message is caught: $line" "scripts/ci-checks.sh prints an unsanitized name" "$(check_unsanitized "$tmp/fxs")"
done
# shellcheck disable=SC2016
for line in '  err "Unreplaced placeholder in $sf"' "  die \"bad \$f_diff\"" '  # err "x $f"' \
            "  printf '%s\\n' \"\$f\" | grep -q x"; do
  fxs; printf '%s\n' "$line" >> "$pc"
  report "fixture: a safe line isn't flagged: $line" "$(check_unsanitized "$tmp/fxs")"
done
fxs
# shellcheck disable=SC2016
printf '  sf=$(se_safe "$f")\n' >> "$pc"
expect_fail "an unchecked se_safe call is caught" ".githooks/pre-commit doesn't check se_safe's status" "$(check_se_status "$tmp/fxs")"
fxs
# shellcheck disable=SC2016
edit_fx "$ci" 's/printf '"'"'%s\\n'"'"' "$added" | grep -qE/printf '"'"'%s\\n'"'"' "$added_n" | grep -qE/'
expect_fail "a decision on numbered lines is caught" "decides on \$added_n, not a cut -f2- capture" "$(check_decisions "$tmp/fxs")"
fxs
# shellcheck disable=SC2016
edit_fx "$pc" 's/printf '"'"'%s\\n'"'"' "$f_added" | grep -qE/printf '"'"'%s\\n'"'"' "$f_diff" | grep -qE/'
expect_fail "a decision on the raw diff is caught" "decides on \$f_diff, not a cut -f2- capture" "$(check_decisions "$tmp/fxs")"
for flag in ' -c diff.relative=false' ' -c diff.suppressBlankEmpty=false' ' --no-color' ' --submodule=short'; do
  fxs; edit_fx "$ci" "s/$flag//"
  expect_fail "a git diff without$flag is caught" "runs git without$flag" "$(check_diff_flags "$tmp/fxs")"
done
fxs; edit_fx "$pc" '/^unset GIT_DIFF_OPTS$/d'
expect_fail "a script that keeps GIT_DIFF_OPTS is caught" ".githooks/pre-commit doesn't unset GIT_DIFF_OPTS" "$(check_diff_flags "$tmp/fxs")"
fxs
# shellcheck disable=SC2016  # the $... is the fixture's sed text
edit_fx "$ci" 's|"$from" "$head" -U0 2>/dev/null)|"$from" "$head" -U0)|'
expect_fail "a git call that shows git's stderr is caught" "scripts/ci-checks.sh:" "$(check_git_quiet "$tmp/fxs")"
expect_fail "...naming the missing redirect" "runs git without 2>/dev/null" "$(check_git_quiet "$tmp/fxs")"
fxs; printf 'git diff --cached --name-only\n' >> "$pc"
expect_fail "a bare git command is caught" ".githooks/pre-commit:" "$(check_git_quiet "$tmp/fxs")"
expect_fail "...as running outside a capture" "runs git outside a \$( ) capture" "$(check_git_quiet "$tmp/fxs")"
fxs
# shellcheck disable=SC2016  # the $... is the fixture's sed text
edit_fx "$pc" 's/| se_where "$sf"$/| se_where "$f"/'
expect_fail "se_where handed a raw name is caught" ".githooks/pre-commit passes se_where an unsanitized path" "$(check_se_where "$tmp/fxs")"

echo
echo "Results: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
