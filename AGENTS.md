# Project Conventions for AI Agents

> **This file is the single source of truth for how AI coding agents (Claude Code, Codex, Cursor, etc.) work in this repository.**
> It is read at the start of every session by every agent.
> `CLAUDE.md` points here so Claude Code and Codex follow the same procedure.
>
> **Setting up?** The conventions here are only *enforced* once the hooks are installed and the CI check is required on `main`. Follow the Setup section of [`README.md`](./README.md) before relying on any gate.

---

## Quick Summary — Read this before your first pull request

**Why `/docs/` exists — the one sentence that explains everything else:** the docs folder is the project's *living memory and source of truth*, built and maintained so that an agent who has read **only `/docs/`** can make a commit with high confidence that it will **not break an existing route, data contract, integration, or behavior**. Every rule below serves that goal. If a doc isn't complete enough or grounded enough in real code to support a safe autonomous commit, it isn't done — see the **Grounding & Completeness Protocol** in § 6.

1. **Every session starts by reading `/docs/` and the task list.** No exceptions. If `/docs/` has not been bootstrapped (no `contracts.md` yet), the *only* job for that session is to build it (§ 6). The contract-critical inventory lives in `/docs/contracts.md` — the exhaustive, code-grounded list of every route, data contract, event, integration, environment variable, and invariant. Read it before changing anything.
2. **6 agents** — five reviewers and a coordinator (§ 1) — review changes in **one round**, scaled by **risk tier** (§ 5). The owner approves the plan before any code (§ 7 step 4b).
3. **Each agent has redlines** in `.claude/agents/*.md` — non-negotiable lines. Crossing one BLOCKs the merge unless the owner explicitly accepts it on the record.
4. **Major decisions** also run through **4 strategic lenses** (§ 4). Surface conflicts between lenses; don't paper over them.
5. **Tasks live one-per-file** in `/tasks/T-NNN.md`. Update the task file in the same pull request that delivers the work.
6. **`/docs/*` requires unanimous 6-agent consensus** to edit.
7. **The owner reviews and merges every pull request.** Agent sign-off does not replace that.
8. **Trivial changes** (typo / lockfile bump) skip agent review and use the standing task `T-000`. See § 5.
9. **Hard gates** are in § 8. No exceptions.

If anything below contradicts this summary, the section below wins — flag the contradiction so it gets fixed.

---

## 0. Session Start Procedure — DO THIS FIRST

Every agent — regardless of which tool invoked it — must run this procedure before answering the user's first request of a session.

### Step 1 — Read the docs folder
1. Check whether `/docs` exists at the root of the repo.
2. If it exists, **read every file in it**. This is the repo's living memory: architecture, **contracts (every route, data contract, event, integration, env var, invariant)**, data model, decisions.
3. Briefly acknowledge to the user what you loaded (one line is enough — e.g. *"Loaded 4 docs: architecture.md, contracts.md, data-model.md, decisions/0001…"*).
4. **Treat `contracts.md` as binding.** Before you add, change, or remove any route, schema field, event, public function signature, integration call, environment variable, or other documented contract, find it in `contracts.md` first. If your change would alter or remove something listed there, it is a **contract change** — call it out explicitly to the user, follow the regression-safety steps in § 7, and update `contracts.md` in the same pull request (which means the `/docs/*` consensus gate applies). If you discover a contract in the code that is **not** documented, that is a gap — surface it; don't silently rely on it.

### Step 2 — Read the tasks ledger
1. List the tasks at a glance: `grep -HE '^(title|state):' tasks/T-*.md`
2. For any **in-flight** task that looks relevant, open its file at `tasks/T-NNN.md` for full context (description, acceptance criteria, activity log).
3. If the user's request relates to an existing task, reference its ID (`T-NNN`) in your reply rather than starting a parallel thread of work.
4. New task? Copy `tasks/_TEMPLATE.md`, pick the next free ID, set `state: proposed`. **One file per task.**

### Step 3 — If `/docs` is not yet bootstrapped
`/docs` counts as **not bootstrapped** when there is no `docs/contracts.md`, whatever else the folder holds — the `docs/README.md` this starter ships does not count as documentation, and neither does any pre-existing content in an adopted project's `docs/`. That content is input to the bootstrap, not living memory: read it, but trust nothing in it until it has passed § 6.0 review. If an adopted project already has a `docs/contracts.md` of its own, move it out of `docs/` in its own commit before adopting (root `README.md`, *An existing project*) so the bootstrap runs and rebuilds it to § 6.0. When `T-001` completes, every pre-existing file has either been folded into the reviewed docs or moved out of `docs/`; nothing unreviewed stays in living memory. This is the **first and only task** for the session until it's resolved. Tell the user:
> *"This project's `/docs` has not been bootstrapped yet. Per project convention, before any feature work I need to build it — not as a summary, but as a complete, code-grounded source of truth (every route, data contract, integration, env var, and invariant) so that future commits can be made safely without breaking what already exists. I'll have all six agents review it to unanimous consensus, then we can start on what you actually asked for."*

Then run the **Docs Bootstrap Workflow** (§ 6), holding every doc to the **Grounding & Completeness Protocol** (§ 6.0): grounded in real code, no invented facts, exhaustive where it's a contract. The bootstrap subtasks are already seeded in `/tasks/` as `T-001` and `T-001.1` through `T-001.5`.

### Step 4 — Unanimous-consensus rule for `/docs`
No agent may add, edit, or remove anything in `/docs` unilaterally. Every change requires sign-off from **all 6 agents** (§ 1). The Review Coordinator drives this. Reason: docs are load-bearing for every future session — one wrong fact propagates forever.

> **If consensus stalls:** surface the deadlock to the owner with each side's position stated plainly. The owner decides, and the reasoning is recorded as an Architectural Decision Record.

> **Note:** `/tasks/*` does **not** require consensus — it's updated as part of the normal flow for the underlying work. Only `/docs/*` carries the consensus gate.

---

## 1. The Agent Team (5 reviewers + coordinator)

| # | Agent | Role | Wins on |
|---|-------|------|---------|
| 1 | **Product** | Requirements, acceptance criteria, scope, usability, accessibility | Scope and user-facing decisions |
| 2 | **Architect** | Architecture, security, dependencies, contracts | Security — always |
| 3 | **Engineer** | Routes, server logic, integrations, user interface components, client code | Application logic & feasibility |
| 4 | **Data Engineer** | Schema, queries, data accuracy, migrations | Schema & queries |
| 5 | **Verifier** | Tests at every level, Continuous Integration, deployment safety | Test coverage — always. *"We'll add tests later"* is never acceptable |
| 6 | **Review Coordinator** | Picks the tier, dispatches reviewers, gathers sign-offs, records the review | Process — owns the gate; can BLOCK on procedural failures |

Detailed role definitions and redlines live in `.claude/agents/*.md`.

- **The main session acts as Review Coordinator.** It follows `.claude/agents/review-coordinator.md` and dispatches the five reviewers itself.
- **Reviewers are read-only.** They review and report; the main session does all writing.
- **"PASS — nothing in my domain" is a valid sign-off.** A project with no user interface or no datastore should not get invented concerns. An abstention is not a sign-off.

---

## 2. Review Cycle (one round)

Reviewers run **in parallel, in a single round**. The coordinator hands each one the plan or the diff plus the task file — the material, not its own conclusions — collects the verdicts, and collates one result: **PASS | PASS WITH ITEMS | BLOCK**. Blockers are resolved before moving on, never deferred.

Which reviewers run, and whether the plan is reviewed as well as the build, depends on the tier (§ 5).

---

## 3. Conflict Resolution

When agents disagree, these defaults apply unless explicitly overridden by the owner:

- **Product vs Engineer** — Product wins on user-facing. Engineer wins on feasibility. If Product wants something expensive, Product must propose a simpler alternative.
- **Engineer vs Data** — Data wins on schema/queries. Engineer wins on application logic.
- **Architect vs Everyone** — Architect wins on security.
- **Product vs Everyone** — Product wins on scope.
- **Verifier vs Everyone** — Verifier wins on test coverage.
- **Review Coordinator vs Everyone** — Coordinator wins on process. Can BLOCK if sign-offs are missing or the review isn't recorded.

Unresolvable conflicts are surfaced to the owner with each side's position stated plainly. **A redline is not something the owner overrides informally** — crossing one requires their explicit OK recorded in the task's activity log (§ 8).

---

## 4. The 4 Strategic Lenses

Every **major** decision — architecture, feature scope, tooling, or anything else that shapes the direction of Glucoscope — is evaluated through all 4 lenses **before** implementation.

1. **Value and cost** — Is this worth my time and money? What does it cost to run? Any vendor lock-in, licence or third-party risk?
2. **User** — Will the people this is built for actually adopt it? Does it make their work easier, or does it add friction?
3. **Maintainer** — Will I be glad to own this code a year from now? Is the design respectful of my future time?
4. **Scope and timing** — Is this buildable in a reasonable timeframe? What are the dependencies and unknowns? Is this the right thing to build *right now*, or should something else be ahead of it?

**Surface conflicts between lenses explicitly.** If one lens loves it and another hates it, that's a red flag that must be resolved before proceeding — not papered over.

---

## 5. When to Run What — the three tiers

| Tier | What qualifies | Process |
|------|----------------|---------|
| **Trivial** | Typo fixes, dependency lockfile bumps, comment-only edits, formatter-only churn, generated-file refreshes | No agent review. Hooks and CI only. Commits reference the standing task `T-000`. No plan approval. |
| **Standard** | A behavior change that touches no documented contract, no schema, no authentication/authorization, and adds no dependency | Owner approves a short plan (§ 7 step 4b). One **build** review by Engineer + Verifier; Product joins for user-interface changes, Data Engineer for query changes. |
| **Risky** | Any change to a documented contract; schema or migration work; authentication, authorization or secrets; a new dependency; a new feature or user interface screen; an architecture decision; **any `/docs/*` edit**; any change to `.claude/agents/*.md`, `.githooks/`, `scripts/` or `.github/` | All five reviewers review the **plan**; owner approves; all five review the **build**. 4 lenses when it is a major decision. Contract changes also need the regression-safety check (§ 7) and `contracts.md` updated in the same pull request. `/docs/*` edits need unanimous 6-agent consensus. |

- **The tier is stated in the plan-approval ask**, so the owner sees it and can raise it.
- **When in doubt, go up a tier.** The Review Coordinator BLOCKs mis-classifications.

> **What does NOT qualify as Trivial:** any behavior change, any user-visible change, any new dependency (even a patch bump if a transitive carries a known security vulnerability), any schema change, any change that touches `/docs/*`, `.claude/agents/*.md` (including redlines), `.githooks/`, `scripts/` or `.github/`, any security-relevant change.

---

## 6. Docs Bootstrap Workflow

Triggered when `/docs` is not yet bootstrapped at session start: there is no `docs/contracts.md` (§ 0 Step 3).

> **The standard the bootstrap must meet.** The bootstrap is not "write some docs about the project." It is: *produce a living memory complete and accurate enough that a future agent who has read only `/docs/` can make a commit with high confidence it will not break an existing route, data contract, integration, or behavior.* A doc that reads well but omits a route, mis-states a schema, or invents a fact that isn't in the code is **worse than no doc** — it produces confident, wrong commits. Every doc is held to the **Grounding & Completeness Protocol** below before any agent may sign off.

### 6.0 Grounding & Completeness Protocol (applies to EVERY doc)

No agent may sign off on a doc — at bootstrap or any later edit — unless it satisfies all of the following. The Review Coordinator BLOCKs any doc that doesn't.

1. **Grounded, not guessed.** Every factual claim is traceable to something real in the repository — a file, a route definition, a schema/migration, a config key, a CI workflow, an infra manifest. Where practical, cite the path (e.g. *"see `src/routes/billing.ts`"*). If the codebase is empty (greenfield), say so explicitly and mark the doc as **forward-looking** (describes the intended state) rather than **descriptive** (describes what exists) — never blur the two.
2. **No invented facts.** If a fact can't be confirmed from the code or from the human user, it does **not** go in the doc. Write `UNKNOWN — needs human confirmation` and open a follow-up task. A plausible guess that looks like a confirmed fact is the single most dangerous failure mode for living memory; an honest `UNKNOWN` is safe.
3. **Exhaustive where it's a contract.** For anything an autonomous commit could break — routes/endpoints, request/response shapes, event schemas, public function/module signatures, database tables and columns, environment variables, feature flags, third-party integrations, cron jobs, queues — the doc (or `contracts.md`) must enumerate **every** instance, not a representative sample. "etc." and "for example" are not acceptable in a contract inventory. If the list is long, it's still complete; length is not an excuse for sampling.
4. **States invariants and breakage modes.** Each contract entry notes what must stay true (the invariant) and what would break if it changed (who calls it, what depends on it). This is what lets a future agent reason about blast radius before editing.
5. **Verification recorded.** The drafting agent states *how* the doc was verified against the code — e.g. "enumerated routes by grepping the router definitions and cross-checking the OpenAPI spec; reconciled against integration tests." The reviewing agents check the doc against the code themselves, not just against the prose. A doc whose claims weren't independently checked against the source does not pass.
6. **Freshness contract.** Each doc names what code paths, when changed, require it to be updated (a "update-this-doc-when" footer). This is what keeps living memory from rotting — § 7 ties commits that touch those paths back to the doc.

A doc that cannot yet meet (3) because the relevant subsystem doesn't exist yet is fine — mark it forward-looking and list the contracts as "planned." A doc that *claims* completeness it doesn't have is a BLOCK.

### The bootstrap, in order

All of it completes before feature work begins. The main session drafts; each doc's named owner reviews it first and owns its completeness.

1. **`contracts.md`** (`T-001.1`; Engineer leads, with Architect and Data Engineer) — the exhaustive, code-grounded inventory of every route/endpoint, request/response contract, event/message schema, public interface, integration, environment variable, feature flag, and cross-cutting invariant. This is the single most important doc for safe autonomous commits. It must satisfy § 6.0(3) — enumerate **everything**, no sampling.
2. **`architecture.md`** (`T-001.2`; Architect) — system overview, trust boundaries and security model, plus sections for the **stack** (what is used and why), **testing** (levels, how to run them, the regression-safety check) and **deployment** (environments, CI, rollback).
3. **`data-model.md`** (`T-001.3`; Data Engineer) — every table/column, indexes, migration approach, and *how to change the schema safely*. If the project has no datastore, the task is closed as **N/A** with the reason and no file is written.
4. **`decisions/`** (`T-001.4`; Architect) — skeleton plus Architectural Decision Record 0001 capturing the foundational stack choice.
5. **Consensus review** (`T-001.5`; Review Coordinator) — all six agents sign off, **each doc is verified against § 6.0**, and only then do files land in `/docs/`.

**The `/docs/` skeleton:**

```
/docs
├── README.md              # how to use this folder; consensus rule restated
├── contracts.md           # ⭐ EXHAUSTIVE inventory: every route, data contract, event,
│                          #    integration, env var, flag, invariant. Code-grounded.
├── architecture.md        # system overview, trust boundaries, stack, testing, deployment
├── data-model.md          # only if there is a datastore: every table/column + safe-change rules
└── decisions/             # Architectural Decision Records
```

Split a section out of `architecture.md` into its own file only when it outgrows the page. On a large codebase `contracts.md` may point to generated/machine-readable sources (OpenAPI, schema dumps) — that's fine, as long as the pointer is exact and the generation is reproducible. A hand-wavy summary is not.

---

## 7. Branch & Commit Workflow

All work happens on feature branches. **No direct pushes to `main`.**

**Branch naming:**
- `feat/<short-name>` — new features
- `fix/<short-name>` — bug fixes
- `chore/<short-name>` — infra, docs, process
- `refactor/<short-name>` — restructuring without behavior change

**Flow:**
1. **Open** (or update) the task file at [`tasks/T-NNN.md`](./tasks/). New tasks start as `proposed` — copy `_TEMPLATE.md` and pick the next free ID. (Trivial tier: use `T-000` and skip to step 5.)
2. Create branch from `main`. Fill in **branch** in the task's frontmatter; append a line to the activity log.
3. **Plan** the work — what changes, which files, what approach, and which **tier** (§ 5).
4. **Risky tier:** run the agent review on the **plan** — get every reviewer's sign-off *before* writing code.

   **4b. Human gate — the owner approves the plan; record their exact words and the date in the task's activity log.** An agent never approves a plan, and never records an approval it didn't receive. Ask once, with a one-screen plain-language summary that states the tier; the owner replies yes, no, or what to change. Silence or a timeout is never a yes. Record `- YYYY-MM-DD — plan approved by <name>: "<their exact words>" (in session)`, and only then update **State → `in-progress`**. The full rules: [`tasks/README.md#plan-approval`](./tasks/README.md#plan-approval).

5. **Build** — implement the approved plan.
6. Run the agent review on the **build** — the reviewers for the tier (§ 5).
7. **Test** — automated tests, not manual checks. Every code path exercised.
8. **Regression-safety check (mandatory before commit).** Prove the change did not silently break a documented contract:
   - Diff your change against `/docs/contracts.md`. For every route, schema field, event, public signature, integration, env var, or flag your change touches, confirm it was *intended* and that the change is reflected back in `contracts.md` (and `data-model.md` as applicable) **in this same pull request**.
   - If you changed or removed something in `contracts.md`, that is a **contract change**: it requires the `/docs/*` unanimous-consensus gate, an explicit note of the blast radius (who/what depends on it), and either backward compatibility or a documented migration/deprecation path.
   - Run the test levels that exercise the touched contracts (contract tests, integration tests, end-to-end). A green unit suite alone does not satisfy this step.
   - State in the task's `## Review` section: *"Regression-safety: contracts touched = […]; reflected in docs = yes/no; compatibility = backward-compatible | migration at <path>."* "None" is a valid answer and must be stated explicitly, not omitted.
9. **Commit** — only after all required agents sign off, tests pass, and the regression-safety check is recorded. **Include the task-file update in this same commit** (not a follow-up PR): set **State → `completed`**, fill in **branch** and **pr** once known (amend the last commit, or push it as the PR's final commit), record the review (§ 9), and append to the activity log. See the note below on why marking `completed` pre-merge is safe.
10. **Push** the feature branch after sign-off.
11. Open a pull request using `.github/pull_request_template.md`. Add the PR number to the task file's `pr:` field and push that as the final commit.
12. **Human review:** the owner reads the pull request and merges it. Agent sign-off does not replace this. Any diff under `.githooks/`, `scripts/` or `.github/` is named in the PR summary so the owner reads it.
13. Continuous Integration must pass before merge. The procedure checks run server-side via `scripts/ci-checks.sh` (the CI mirror of `.githooks/`) — bypassing local hooks with `--no-verify` does not bypass Continuous Integration.
    **Wait for it yourself.** Don't end your turn asking a human to tell you when checks finish. Read the result for your latest commit when it should be ready, using a timer or your tool's CI monitor if it has one, then act on it. Fix the cause of a failure under the normal gates, never by loosening a gate, allowlist or test. Once green, continue the remaining steps; green doesn't replace step 12. If your tool can't wait, checks run far past their usual time, or a second fix fails, stop, say so and name what's left. A check that never appears is a finding to report, and pending or missing is never a pass.

> **Why marking `completed` before merge is safe.** The ledger update rides in the *same* PR as the work, so a `completed` state only reaches `main` when that PR merges. A task shown `completed` on `main` is therefore — by construction — merged. An abandoned PR's `completed` line never reaches `main`; a revert reverts the ledger line too. A *feature branch* may briefly show `completed` while its PR is open — read that as "claimed done, pending merge."

### Continuous Integration

[`.github/workflows/checks.yml`](./.github/workflows/checks.yml) runs on every PR and push to `main`. It runs with least privilege (no token permissions by default, read-only contents, no saved git credentials, actions pinned by commit SHA) and uses `pull_request`, never `pull_request_target`.

- It calls [`scripts/ci-checks.sh`](./scripts/ci-checks.sh) — the single source of truth for the procedure gates (placeholders, secrets, task-ID, `/docs/*` consensus).
- On a PR build it runs the **target branch's** copy (and its `.placeholder-allow`) through [`scripts/ci-pr-checks.sh`](./scripts/ci-pr-checks.sh), so a PR can't loosen the gate it is judged by; a gate change applies from the next PR on.
- The gate scripts' own tests run through `scripts/test/run-all.sh`.

> ⚠️ **Nothing is enforced until the check is required.** CI that runs but isn't required on `main` blocks nothing, and `--no-verify` bypasses the hooks. Require the check in branch protection (`README.md`, Setup).

### Hooks (one-time setup, every fresh clone)

Run `sh scripts/setup-hooks.sh` once after cloning. It sets `core.hooksPath` to `.githooks/` so the hooks run on every commit and push. The hooks enforce:

- No direct commits to `main` / `master` / `production` / `release` / `trunk`.
- No `[insert … here]` placeholders in staged content.
- Basic secret scan (AWS / GitHub / Slack / OpenAI / Anthropic tokens, private-key blocks).
- Task ID (`T-NNN`) required in every commit message.
- `unanimous-consensus: T-NNN` required in any commit touching `/docs/*`.
- No force-push to protected branches.

---

## 8. Hard Gates — No Exceptions

> **Mechanically enforced vs. review-enforced.** The hooks and the CI mirror enforce the branch, placeholder, secret, task-ID and consensus-trailer rules — a machine blocks them. The rest — marked *(review-enforced)* — depend on the review and on the owner. They are no less mandatory, but be honest that nothing mechanical catches them.

- No code without a plan the owner has approved (§ 7 step 4b), Trivial tier excepted. *(review-enforced)* The record is written by the agent; the owner checks the quote when reading the PR.
- No commit without the agent sign-offs its tier requires. *(review-enforced)*
- No merge without the owner. Agents open pull requests; they do not merge to `main` unless the owner says to, for that pull request.
- No commit without passing automated tests.
- No manual-only testing — every test runs in Continuous Integration.
- No intentional tech debt — build it right or don't build it.
- No edits to `/docs/*` without unanimous 6-agent consensus. The commit trailer is machine-checked; the sign-offs behind it are recorded in the task file. *(the sign-offs are review-enforced)*
- **No agent redline crossed without the owner's explicit OK**, recorded in the task's activity log in their exact words. When the decision is durable, it is also written up as an Architectural Decision Record. Redlines live in `.claude/agents/*.md` and are non-negotiable by default.
- No Trivial-tier claim on a change that doesn't qualify (§ 5).
- **No gate, allowlist or test loosened to make a check pass.** A change to `.githooks/`, `scripts/` or `.github/` is Risky tier and is named in the PR summary.
- **No commit that touches a documented contract without updating `/docs/contracts.md` (and `data-model.md` as applicable) in the same pull request.** Living memory that lags the code is how confident-but-wrong commits happen. A change to a route, schema field, event, public signature, integration, env var, or flag and its doc are one atomic change, not two.
- **No doc signed off that violates the Grounding & Completeness Protocol (§ 6.0)** — invented facts, sampled-not-exhaustive contract lists, or unverified claims are a BLOCK, not a warning.

---

## 9. Review Record

Every Standard or Risky review is recorded in the task file's `## Review` section — one block per review (plan, build). This is the evidence behind the agent sign-offs and the consensus trailer.

```markdown
## Review

### <plan | build> — YYYY-MM-DD — Tier: Standard | Risky
**Status:** PASS | PASS WITH ITEMS | BLOCK

- Product — PASS | PASS WITH ITEMS | BLOCK | not required — <one line>
- Architect —
- Engineer —
- Data Engineer —
- Verifier —
- Review Coordinator —

**Blockers resolved:** …
**Open items (fix before next review):** …
**Lenses (major decisions only):** Value and cost · User · Maintainer · Scope and timing — <conflicts, or "none">
**Regression-safety:** contracts touched = […]; reflected in docs = yes/no; compatibility = backward-compatible | migration at <path>
```

---

## 10. Stack-Agnostic Placeholders

This starter is intentionally stack-neutral. Replace the bracketed placeholders below when you start a project. Search the repo for `[insert ` to find every one.

| Placeholder | Replace with |
|-------------|--------------|
| `[insert product name here]` | The product/project this repo builds |
| `[insert language here]` | TypeScript / Python / Go / Rust / etc. |
| `[insert package manager here]` | pnpm / npm / yarn / pip / poetry / cargo / etc. |
| `[insert frontend framework here]` | Next.js / Remix / SvelteKit / Vue / plain React / none |
| `[insert backend framework here]` | Node + Express / FastAPI / Go + chi / Rails / .NET / none |
| `[insert database here]` | Postgres / MySQL / SQLite / DynamoDB / Mongo / none |
| `[insert hosting platform here]` | Vercel / Fly.io / Render / Cloudflare / a VPS / etc. |
| `[insert secret manager here]` | Doppler / 1Password / the host's secret store / etc. |
| `[insert test runner here]` | Vitest / Jest / Pytest / Go test / etc. |

Agents should **flag** any unreplaced `[insert …]` they encounter during review.

---

## 11. Tool-Specific Notes

- **Claude Code** — Reviewers live in `.claude/agents/*.md` and are invoked via the `Task` / `Agent` tool by the main session. `CLAUDE.md` points back to this file.
- **Codex** — Reads this `AGENTS.md` natively. The `.claude/agents/*.md` files double as plain-markdown role briefs; paste one into a prompt when emulating a reviewer.
- **Cursor / other agents** — Same convention: point the tool at `AGENTS.md` first.

The goal is **identical procedure regardless of which tool is used**.
