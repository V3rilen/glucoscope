#!/usr/bin/env sh
# One-time setup: point git at the project's .githooks/ directory.
# Run once per fresh clone. Idempotent.

set -e

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "Not in a git repository." >&2
  exit 1
fi

git config core.hooksPath .githooks
chmod +x .githooks/pre-commit .githooks/commit-msg .githooks/pre-push 2>/dev/null || true

cat <<EOF
Hooks installed.
  git will now use .githooks/ for pre-commit, commit-msg, and pre-push.
  CI mirror: scripts/ci-checks.sh, run by GitHub Actions (.github/workflows/checks.yml).
  NOT enforced until main requires its checks.

To opt out (not recommended):
  git config --unset core.hooksPath
EOF
