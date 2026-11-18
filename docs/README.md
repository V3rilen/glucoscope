# `/docs` — Project Living Memory

This folder is the project's **living memory and source of truth**. Every AI agent (Claude Code, Codex, Cursor, etc.) is required by `AGENTS.md` § 0 to read every file here at the start of every session before doing any work.

> **Status of this file:** *descriptive*: the rules it restates exist in `AGENTS.md`, the hooks and the task files, and the docs in the table below were written by the T-001 bootstrap. `AGENTS.md` is authoritative; if this file and `AGENTS.md` disagree, `AGENTS.md` wins and this file is wrong.

## The bar this folder must meet

The test for whether `/docs/` is good enough is a single sentence:

> **An agent who has read only `/docs/` should be able to make a commit with high confidence that it will not break an existing route, data contract, integration, or behavior.**

That is a much higher bar than "documentation that describes the project." It means the docs must be **complete enough** to enumerate everything an autonomous change could break, and **accurate enough** that nothing in them is a plausible-sounding guess. Both are required by the **Grounding & Completeness Protocol** in `AGENTS.md` § 6.0 — read it before drafting or reviewing any doc. The protocol is review-enforced: no hook or CI check verifies grounding; the reviewers do.

## Why this folder matters

Without it, every session starts cold. The agents re-derive architecture from grep, re-discover conventions by trial and error, and — worst — invent **wrong** facts that look plausible. A confident agent acting on a wrong fact ships a confident, wrong commit. This folder prevents that — but only if it is grounded in real code and kept current with it.

## The Grounding & Completeness Protocol (summary)

Full version in `AGENTS.md` § 6.0. No agent may sign off on a doc unless it is:

- **Grounded, not guessed** — every claim traceable to a real file / route / schema / config / workflow; cite paths where practical.
- **Free of invented facts** — anything unconfirmed is written `UNKNOWN — needs human confirmation`, with a follow-up task opened, never as if settled.
- **Exhaustive where it's a contract** — routes, request/response shapes, events, public signatures, tables and columns, env vars, flags, integrations, cron jobs and queues are listed in full, not sampled. No "etc." in a contract inventory.
- **Explicit about invariants & blast radius** — each contract notes what must stay true and what depends on it.
- **Verified** — the drafting agent records how it checked the doc against the code; reviewers re-check against the source, not just the prose.
- **Under a freshness contract** — each doc names the code paths that, when changed, require it to be updated (an "update-this-doc-when" footer).

If the codebase is empty (greenfield), mark the doc **forward-looking** (intended state) rather than **descriptive** (what exists). Never blur the two.

## Hard rule — unanimous consensus

**No file in this folder may be added, edited, or removed without sign-off from all 6 agents** defined in `AGENTS.md` § 1. The Review Coordinator (`.claude/agents/review-coordinator.md`) drives this. One wrong fact here propagates into every future session, so the bar is deliberately high.

If a single agent BLOCKs a `/docs/*` change, the change does not land until the block is resolved. If consensus stalls, the deadlock goes to the owner with each side's position stated; the owner decides, and the reasoning is recorded as an Architectural Decision Record (`AGENTS.md` § 0 Step 4).

**What is machine-checked, and what is not.** A commit touching `/docs/*` must carry `unanimous-consensus: T-NNN` in its message.
- `scripts/ci-checks.sh` checks this for every commit in the range that adds, edits or removes a `/docs` file.
- The `commit-msg` hook checks it locally for commits that add or edit a `/docs` file. It does not catch a commit that only deletes one, and it skips `Merge`, `Revert`, `fixup!`, `squash!` and `amend!` commits; CI is the backstop for those.
- The hook runs only once installed (`scripts/setup-hooks.sh`), and `--no-verify` skips it. CI (`.github/workflows/checks.yml`) runs on every pull request and every push to `main` regardless, but blocks nothing until its check is required on `main`.
- Both check only that the text is present. The six sign-offs behind it are recorded in the task file's `## Review` section (`AGENTS.md` § 9), and checking those is the Review Coordinator's job during the review and the owner's when reading the pull request.

## What goes here

**This README alone does not count as documentation, and neither does an adopted project's pre-existing `docs/` content** (input to the bootstrap, not living memory; `AGENTS.md` § 0 Step 3). While `/docs` holds no `contracts.md`, the folder is not yet bootstrapped, and running the **Docs Bootstrap Workflow** (`AGENTS.md` § 6) is the first and only task for the session until it is done. All of the following is required before any feature work begins, except where the table says N/A.

| File | Owner | Purpose |
|------|-------|---------|
| `contracts.md` ⭐ | Engineer (lead), with Architect and Data Engineer | **The exhaustive, code-grounded inventory** of every route/endpoint, request/response contract, event/message schema, public interface/signature, data contract (every table/collection and its consumers), third-party integration, environment variable, feature flag, cron/queue, and cross-cutting invariant. The single most important doc for safe autonomous commits. Must be complete (§ 6.0(3)), not a sample. May point to reproducible machine-readable sources (OpenAPI / schema dumps) as long as the pointers are exact. Task `T-001.1`. |
| `architecture.md` | Architect (the Verifier reviews the testing and deployment sections) | System overview, components, data flow, trust boundaries and security model, identity and secrets approach, failure modes — plus sections for the **stack** (what and why), **testing** (levels, how to run, the regression-safety check) and **deployment** (environments, CI, rollback). Task `T-001.2`. |
| `data-model.md` | Data Engineer | **Only if the project has a datastore.** Every table/collection with columns, types, indexes and foreign keys; personally identifiable information classification; each table's consumers and blast radius; the migration approach and **how to change the schema safely**. With no datastore, no file is written: task `T-001.3` is closed as N/A with the reason, and `contracts.md` says so under data contracts. |
| `decisions/` (skeleton + Architectural Decision Record 0001) | Architect | One Architectural Decision Record per significant decision. Past records are never edited — supersession only (`tasks/T-001.4.md`). |

Split a section out of `architecture.md` into its own file only when it outgrows the page (`AGENTS.md` § 6). Any other file added here carries the same consensus rule.

## How to use this folder during a session

The authoritative procedure is `AGENTS.md` § 0, which also covers reading the task ledger. For the `/docs` part of it:

1. List every file under `/docs/`. If there is no `contracts.md`, stop and run the bootstrap (`AGENTS.md` § 0 Step 3).
2. Read every file.
3. Acknowledge to the user what you loaded — one line: *"Loaded N docs: architecture.md, contracts.md, …"*
4. **Before changing anything, check `contracts.md`.** If your change touches a documented route, schema field, event, public signature, integration, env var, or flag, it is a contract change: call it out to the user, run the regression-safety check (`AGENTS.md` § 7), and update `contracts.md` (and `data-model.md` as applicable) in the same pull request — which brings the consensus gate above into play.
5. If you find a contract in the code that is **not** documented here, that is a gap: surface it; don't silently rely on it.

**You are the owner reading a pull request.** For any `/docs/*` change, check that the task file records six sign-offs in its `## Review` section and your own plan approval in its activity log, and that the commit carries the `unanimous-consensus:` trailer.

## Anti-patterns

- ❌ Editing a doc to match a code change without running the consensus review.
- ❌ Adding a "draft" doc that no one's signed off on — drafts live on a branch, not in `/docs/`.
- ❌ Leaving an unreplaced `[insert … here]` placeholder in a doc. Fill it in or remove the line; if the fact is genuinely not known yet, write `UNKNOWN — needs human confirmation` and open a follow-up task (§ 6.0(2)).
- ❌ **Inventing a fact because it sounds right.** If it isn't confirmed by the code or the human, it's `UNKNOWN`, not a sentence that reads as settled. A plausible guess in living memory is a landmine.
- ❌ **Sampling a contract inventory.** "The main routes are …" or "tables include …" is a BLOCK. Contracts are listed in full or the doc points to an exact, reproducible machine-readable source.
- ❌ **Letting `contracts.md` drift behind the code.** A change to a documented contract and its doc update are one atomic pull request, never "I'll update the docs later."

---

**Verification.** Each claim above was checked against `AGENTS.md` (§ 0, § 1, § 6, § 6.0, § 7, § 8, § 9, § 10), `.githooks/commit-msg`, `scripts/ci-checks.sh`, `scripts/setup-hooks.sh`, `.github/workflows/checks.yml`, `.placeholder-allow`, `.claude/agents/review-coordinator.md`, `tasks/README.md` and `tasks/T-001.md` to `tasks/T-001.5.md`, first by the drafter and then independently by the five reviewers over two rounds; the record is in `tasks/T-003.md`.

**Update this doc when** any of these change: `AGENTS.md` § 0, § 1, § 6, § 6.0, § 7, § 8, § 9 or § 10; the `/docs` consensus check in `.githooks/commit-msg` or `scripts/ci-checks.sh`; `scripts/setup-hooks.sh`; the triggers in `.github/workflows/checks.yml`; this file's entry in `.placeholder-allow`; `.claude/agents/review-coordinator.md`; the plan-approval rules in `tasks/README.md`; the scope or owner of any `tasks/T-001*.md` bootstrap task; the set of docs the bootstrap writes.
