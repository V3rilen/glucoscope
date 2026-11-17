# `.githooks/` — Procedure-Enforcing Git Hooks

Stack-agnostic POSIX shell hooks that enforce `AGENTS.md` procedure at commit and push time.

## Install (one-time, per fresh clone)

```sh
scripts/setup-hooks.sh
```

That sets `core.hooksPath` to `.githooks/` and makes the hooks executable. To opt out (not recommended):

```sh
git config --unset core.hooksPath
```

## What each hook does

| Hook | What it blocks | Why |
|------|----------------|-----|
| `pre-commit` | Direct commit to `main` / `master` / `production` / `release` / `trunk` | `AGENTS.md` § 7 — feature-branch workflow |
| `pre-commit` | Any staged content containing `[insert … here]` placeholders. Each hit is reported as `  <file>: line <n>`, never its content (starter T-024) | `AGENTS.md` § 8 — hard gate |
| `pre-commit` | Staged content containing AWS keys, private-key blocks, GitHub/Slack/OpenAI/Anthropic tokens (basic regex scan). Reports the kind of secret and `  <file>: line <n>`, never the secret (starter T-024) | Architect redline |
| `pre-commit` | (warn only) `/docs/*` change — flags that commit-msg will require the consensus assertion | `AGENTS.md` § 0 |
| `commit-msg` | Commit messages missing a Task ID (`T-NNN` or `T-NNN.M`) | `AGENTS.md` § 7 step 8 |
| `commit-msg` | `/docs/*` change without `unanimous-consensus: T-NNN` in the message | `AGENTS.md` § 8 hard gate |
| `pre-push` | Force-push to a protected branch | Safety |

## Bypass policy

`--no-verify` skips local hooks but **does not skip Continuous Integration**. The same checks run server-side via `scripts/ci-checks.sh`, on GitHub Actions (`.github/workflows/checks.yml`). Once `main` requires those checks, CI blocks the merge. Don't waste a round trip — fix the issue locally.

Genuine false positives (e.g., a regex hit on a legitimate test fixture) are resolved by sanitizing the diff or, as a last resort, an Architectural Decision Record approved by the Directly Responsible Individual.

## Matching CI's shellcheck locally

CI lints `.githooks/*` and `scripts/**/*.sh` with **shellcheck v0.10.0**, pinned by checksum in `.github/workflows/checks.yml` (`SHELLCHECK_VERSION` and `SHELLCHECK_SHA256`). A newer local shellcheck can flag things CI doesn't, and the reverse. To run the exact CI binary on Linux x86_64:

```sh
curl -sSfLo /tmp/shellcheck.tar.xz https://github.com/koalaman/shellcheck/releases/download/v0.10.0/shellcheck-v0.10.0.linux.x86_64.tar.xz
echo "6c881ab0698e4e6ea235245f22832860544f17ba386442fe7e9d629f8cbedf87  /tmp/shellcheck.tar.xz" | sha256sum -c -
tar -xJf /tmp/shellcheck.tar.xz -C /tmp
/tmp/shellcheck-v0.10.0/shellcheck .githooks/pre-commit .githooks/commit-msg .githooks/pre-push scripts/*.sh scripts/test/*.sh
```

On macOS, download the matching `darwin` file from the same release page and verify its SHA-256 against the checksum the release publishes for it, or run the commands above in a Linux container. When the pin is bumped in the workflow, `scripts/test/test-ci-wiring.sh` fails until this section names the new version and checksum.

On Windows, `winget install koalaman.shellcheck` (or `scoop install shellcheck`) installs the current release, which may not be the CI version; run it from Git Bash with the same arguments.

## Customizing for your stack

These hooks are intentionally stack-neutral. Formatter/linter/type-checker checks for `[insert language here]` go in the marked slot in `.github/workflows/checks.yml`.
