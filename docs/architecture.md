# Architecture — Glucoscope

> **Status:** mostly **descriptive** of the week-1 scaffold. Sections marked **Planned** describe owner decisions recorded in `PROJECT_PLAN.md` that are not built yet. Facts found in neither the code nor the plan are written `UNKNOWN — needs human confirmation`, each with a follow-up task.
>
> Exact contracts (routes, env vars, signatures, invariants) live in [`contracts.md`](./contracts.md). This file explains the shape of the system and why it is that way.

## 1. Overview

Glucoscope is a self-hosted, server-rendered web app for viewing blood glucose data from a CGM (uploaded by xDrip+) and sharing it with caregivers (`PROJECT_PLAN.md` § 1). It is a CSE 340 final project.

**What exists today:** a single Node.js process running an Express 5 app that renders LiquidJS templates and holds a PostgreSQL connection pool. It serves a home page, a `/health` check, one stylesheet, and 404 and error pages. There are no users, no stored data, and no xDrip+ endpoint yet.

### Components (all in one process)

| Component | Path | Responsibility |
|---|---|---|
| Entry point | `server.js` | Reads `PORT`, calls `app.listen` |
| App setup | `src/app.js` | View engine, global middleware, route mount, error handlers. Exported without `listen` so tests can import it. |
| Routes | `src/routes/index.js` | Maps URLs to controllers. No logic. |
| Controllers | `src/controllers/homeController.js` | Handle requests, call models, render views |
| Models | `src/models/db.js` | PostgreSQL pool, `query`, `checkConnection` |
| Middleware | `src/middleware/errorHandler.js` | 404 handler and the global error handler |
| Views | `views/layouts`, `views/pages`, `views/partials` | LiquidJS templates. All HTML is rendered on the server. |
| Static assets | `public/` | Served at the site root. Today only `css/styles.css`. |

This is the MVC layout the owner chose (`PROJECT_PLAN.md` § 9, § 13 "Folder structure"). **Planned** directories that don't exist yet: `src/utils/` and `database/`.

### Request flow

```
Browser ──HTTPS──▶ Cloudflare edge ──(origin link: UNKNOWN, T-006)──▶ Node/Express (this repo) ──TCP──▶ PostgreSQL
                                                         │
             static (public/) ◀── M5 ── urlencoded ── no-store ── routes ── 404 ── error handler
```

A request passes through the middleware chain in `contracts.md` § 2. Static files are answered first. Everything else gets `Cache-Control: private, no-store`, then reaches a route or the 404 handler. Any error ends in the global error handler, which always renders HTML and sets the same `Cache-Control` itself, because errors from the form parser or static files never pass the `no-store` middleware.

## 2. Trust boundaries and security model

### Data classification
- **Health data** (glucose readings, manual entries, day comments; **planned**, none stored yet) is **sensitive**. The owner's rule is that admins never see it (`PROJECT_PLAN.md` § 3; `contracts.md` § 9 I8).
- **Personal account data** (**planned**): email, display name, time zone (`PROJECT_PLAN.md` § 10). This is PII.
- **Credentials:** `DATABASE_URL` / `PGPASSWORD` today; password hashes and per-user upload secrets are planned.
- **Logs may contain sensitive data.** The error handler and the pool error listener log **full error objects** (`errorHandler.js:18`, `db.js:7`). Once tables exist, PostgreSQL error details can include row values, which could be health data. How logs are stored, retained and protected is a gap for T-005 (what queries can put into errors) and T-006 (where logs go).
- **Cloudflare decrypts traffic at its edge**, so health data passes through a third party in readable form. The owner has accepted this, and it is to be disclosed in the README (`PROJECT_PLAN.md` § 8).

### Boundaries

| # | Boundary | Today |
|---|---|---|
| B1 | Browser → Cloudflare | HTTPS terminated at Cloudflare (owner decision, `PROJECT_PLAN.md` § 8). Cloudflare configuration is outside the repo. |
| B2 | Cloudflare → origin (Express) | `UNKNOWN — needs human confirmation` (T-006): Tunnel (`cloudflared`, recommended in the plan) or proxied DNS with port forwarding; SSL mode (plan: Full (strict), never Flexible); whether the origin accepts **only** Cloudflare traffic. The app trusts one proxy hop in production (`trust proxy = 1`). |
| B3 | Express → PostgreSQL | TCP using `DATABASE_URL`. No SSL is configured in code; `PGSSLMODE` decides it if set (`contracts.md` § 7.2). The plan says PostgreSQL listens on localhost only, using a non-superuser app role (`PROJECT_PLAN.md` § 8). **Whether that is true on the server is `UNKNOWN` (T-006).** Plaintext DB traffic is acceptable only if PostgreSQL is loopback-only. |
| B4 (planned) | xDrip+ → `/api/v1/entries` | Machine-to-machine JSON, authenticated by the SHA-1 `api-secret` header (`PROJECT_PLAN.md` § 7). **Needs its own threat model before it is built.** Known issue to resolve then: xDrip+ sends the SHA-1 of the secret, and the plan stores `upload_secret_hash` (§ 10). If the stored value is that same SHA-1, **it works as a password**: anyone who can read the database can upload as that user. The fix is chosen in that threat model. |

### Threats per boundary (STRIDE, short form)

| Boundary | Threat | Current mitigation | Gap |
|---|---|---|---|
| B1 | Information disclosure (caching) | `Cache-Control: private, no-store` on every non-static response (`src/app.js:36-39`), and on every error page by the error handler itself (`src/middleware/errorHandler.js:22`) | Cloudflare cache rules are outside the repo: `UNKNOWN` (T-006). Static files and the directory redirect are cacheable (`public, max-age=0`); this is safe only while `public/` holds no user data. |
| B1 | Information disclosure (errors) | Stack traces hidden when `NODE_ENV=production` (`errorHandler.js:27`) | Depends on I1 (`contracts.md` § 9) being set on the server |
| B1 | Tampering / XSS | Liquid `outputEscape: 'escape'` (`src/app.js:16`) | No CSP |
| B1 | Spoofing / elevation | — | No authentication exists yet (planned: `express-session` + bcrypt, `PROJECT_PLAN.md` § 2) |
| B1 | Denial of service | Cloudflare in front (owner decision); urlencoded body limit 100 kb | No rate limiting (planned, `PROJECT_PLAN.md` § 8). `/health` runs a DB query per call and is public. |
| B2 | Spoofing (bypassing Cloudflare to reach the origin directly) | — | `UNKNOWN` (T-006). If the origin is reachable directly, `trust proxy` lets a client forge `X-Forwarded-*`. |
| B2 | Information disclosure | — | Origin TLS / SSL mode `UNKNOWN` (T-006) |
| B3 | Information disclosure / tampering | Parameterized-query rule (`db.js:10`) | DB TLS off unless `PGSSLMODE` is set. Loopback-only and role privileges `UNKNOWN` (T-006). |
| All | Repudiation | — | No request or audit logging. Only ≥500 errors and pool errors go to stderr. |

### Identity and secrets
- No user identity exists yet. Planned: session-based auth (`express-session`, bcrypt, PostgreSQL session store via `connect-pg-simple`); roles `admin`, `clinician`, `user`; caregiving as a `care_links` relationship (`PROJECT_PLAN.md` § 2–4).
- Secrets live in environment variables, loaded from a gitignored `.env` (`.gitignore`, `.env.example`, `package.json` scripts). There is no secret manager. The pre-commit hook and CI scan for common token formats (`.githooks/pre-commit`, `scripts/ci-checks.sh`).

### Absent controls
See `contracts.md` § 10: no auth, sessions, CSRF protection, validation, rate limiting, CSP or HSTS, or request logging. The comment about "secure session cookies" at `src/app.js:28-29` describes a future need; there are no sessions.

## 3. Failure modes

| Failure | Behaviour | Evidence |
|---|---|---|
| DB refuses connections | Pages that don't query the DB still work. `/health` → 503 `{"status":"unavailable"}`, and `err.message` is logged. | `homeController.js:7-10`, `db.js:15-23` |
| DB host unreachable (packets dropped) | With no `connectionTimeoutMillis`, `/health` waits for the operating system's TCP connect timeout (OS-dependent, on the order of minutes on Linux) before returning 503. Cloudflare may time out first. Requests beyond the pool's 10 connections queue with no limit. `PGCONNECT_TIMEOUT` has no effect. Fix: T-006. | `db.js:3`; `node_modules/pg/lib/client.js:116`; `contracts.md` § 1 R2 |
| The error page itself fails to render | Express's built-in final handler responds, with a stack trace unless `NODE_ENV=production` | Express 5 default behaviour; `contracts.md` § 3.3 |
| Idle pool client errors (for example a DB restart) | Logged, and the process keeps running | `db.js:5-8` |
| Uncaught error in a handler | Express 5 forwards sync throws and rejected promises to `errorHandler` → HTML error page (500), full error logged | `errorHandler.js` |
| `listen` fails (port in use) | Throws, and the process exits | `server.js:5-6` |
| Process crash or reboot | Planned: a system service or PM2 restarts it (`PROJECT_PLAN.md` § 8). **What is installed is `UNKNOWN` (T-006).** | — |
| Shutdown | No graceful shutdown hook. The pool is never ended. | `server.js` |

Logging is `console.log` / `console.error` to stdout and stderr only (`server.js:7`, `db.js:7,20`, `errorHandler.js:18`). Full error objects are logged for ≥500 errors and for pool errors. Where logs go on the server is `UNKNOWN` (T-006).

## 4. Cost shape

- One self-hosted machine runs both Node and PostgreSQL, with Cloudflare in front (`PROJECT_PLAN.md` § 1, § 8). All runtime dependencies are open source (§ 5.2). No paid service is referenced in the repo.
- Hardware, power and the Cloudflare plan or tier are `UNKNOWN — needs human confirmation`, and not material to code changes.
- Expected data growth is about 288 CGM readings per user per day, about 105k per year (`PROJECT_PLAN.md` § 9). This is a planning estimate.

## 5. Stack

### 5.1 Choices (why and alternatives: [ADR 0001](./decisions/0001-foundational-stack.md))

| Layer | Choice | Status | Why (from `PROJECT_PLAN.md` § 2) |
|---|---|---|---|
| Language / modules | JavaScript, **ESM only** (`"type": "module"`) | in code | Course rubric forbids `require` |
| Runtime | Node.js **≥ 22.9.0** (`engines`) | in code | `--env-file-if-exists`, `import.meta.dirname` |
| Framework | Express **5.3.0** | in code | Course requirement |
| Views | LiquidJS **10.30.1**, server-rendered, no client framework | in code | Course allows EJS or Liquid; rubric requires SSR |
| Charts | Server-generated inline SVG, no client chart library | planned | Keeps everything SSR |
| Database | PostgreSQL via `pg` **8.23.1** | driver in code, no schema yet | `TIMESTAMPTZ`, window and percentile functions, `ON CONFLICT`, constraints |
| Auth | `express-session` + bcrypt + `connect-pg-simple` | **decided, not installed** | Rubric requires sessions, not JWT |
| Package manager | npm (`package-lock.json`, lockfileVersion 3) | in code | — |
| Hosting | Self-hosted machine behind Cloudflare | decided; live deploy `UNKNOWN` (T-006) | Instructor allows any host |
| Secrets | `.env` file + environment variables | in code | Simple single-host deploy |
| Test runner | built-in `node:test` | in code (T-004, `npm test`) | No extra dependency |

### 5.2 Dependency inventory (from `package-lock.json`)
- **Direct runtime dependencies:** `express` 5.3.0 (MIT), `liquidjs` 10.30.1 (MIT), `pg` 8.23.1 (MIT). No dev dependencies.
- **Full tree:** 81 packages. Licenses: 74 MIT, 6 ISC, 1 BSD-3-Clause. All are permissive.
- **Load-bearing (expensive to replace):** Express (every route and middleware), LiquidJS (every template), and PostgreSQL / `pg` (all planned data, SQL-specific features).
- **Vulnerability scanning:** none. CI runs no `npm audit` or dependency scan. Version ranges in `package.json` are caret (`^`), and the lockfile pins exact versions.

## 6. Testing

### Levels

| Level | Tool | How it runs | Scope |
|---|---|---|---|
| Unit | `node:test` + `node:assert` | `npm test` | `src/models/db.js` exports (`test/db.test.js`); the error handler called directly (`test/errorHandler.test.js`) |
| Integration (HTTP) | `node:test` + `node:http` against the real app on `127.0.0.1`, random port | `npm test` | Every route and middleware contract in `contracts.md` §§ 1–4 (`test/app.test.js`, `test/app.production.test.js`); error handling through a test-only app built around the exported middleware (`test/errorHandler.test.js`) |
| DB integration | `node:test` against a disposable PostgreSQL | not set up; comes with the first table (T-005) | Models and queries |
| End-to-end | — | not planned yet | — |

Each **Guarded by** entry in `contracts.md` names the test file that covers it.

### How it works (T-004)
- **`npm test`** = `node --import ./test/setup.js --test "test/**/*.test.js"`. It uses Node's built-in runner with no test dependency, and it does not load `.env`.
- **One process per file** (the runner's default). `src/app.js` reads `NODE_ENV` once, when it is imported, so production mode has its own file (`test/app.production.test.js`). Every file sets `NODE_ENV` itself before importing the app and restores it afterwards. A shell with `NODE_ENV=production` or a real `DATABASE_URL` does not change the results.
- **No real database.**
  - `test/helpers/db.js` `fakeDb(t, 'healthy' | 'failing' | handler)` replaces `pg.Pool.prototype.query`, which the pool in `src/models/db.js` inherits. No production code changes, and `t.mock` restores it after each test.
  - **Tripwire:** `test/setup.js`, preloaded into every test process, replaces `pg.Client.prototype.connect`, through which every real connection path goes. A global `afterEach` **fails** any test that reached it, even when app code swallows the error (as `checkConnection` does). `test/db.test.js` proves it counts a hit, and `test/tripwire.test.js` runs a deliberately bad test file (`test/fixtures/tripwire-hit.js`) in a child process and proves the hit **fails** it, on whatever Node version runs the suite. Limit: a hit from work that outlives its test is counted against the next test, so tests await every query.
- **HTTP:** `test/helpers/server.js` starts an app on a loopback port and sends raw requests with `node:http`, not `fetch`, because `fetch` percent-encodes `<` and would hide escaping bugs. It ignores a socket reset that arrives after a response (the 413 case), and closes all connections when the file ends.
- **Errors that no production route raises** (thrown, rejected, out-of-range `err.status`) are tested in a test-only app that borrows the real app's views and Liquid engine (`app.engines['.liquid']`; a test fails loudly if Express stops storing it there). Production routes are not changed to make errors testable.
- **Not guarded by a test**, and why (`contracts.md`): `PORT` (only `server.js` reads it; no test starts `server.js`), `DATABASE_URL` (tests never connect; T-005), the production template cache (not observable), the unreachable-database hang (T-006), and the CSS class coupling and the "Not present" middleware list (review only).

**Flake policy:** a flaky test is a bug. Fix it or delete it. Never retry until green.

### Regression-safety check (`AGENTS.md` § 7 step 8), as it applies here
1. List every `contracts.md` entry your diff touches (routes, middleware order, env vars, exports, templates, invariants).
2. For each, find its **Guarded by** test file. If your change alters the contract, change the test in the same PR; if the entry has no test, add one or say in the review why none is possible.
3. Run `npm test` and the gate suites (`sh scripts/test/run-all.sh`).
4. Update `contracts.md` in the same PR, and record the regression-safety line in the task's `## Review`.

## 7. Deployment

### Environments
The repo distinguishes only by `NODE_ENV` (`contracts.md` § 7.1).

| | Development (any `NODE_ENV` other than `production`) | Production (`NODE_ENV=production`) |
|---|---|---|
| Error pages | show the stack trace | hide the stack |
| `trust proxy` | off | `1` |
| Template cache | off | on |
| Start command | `npm run dev` (watch mode) | `npm start` |

No staging environment exists. Other differences (host, DB, Cloudflare) are outside the repo.

### Continuous Integration (as it is)
`.github/workflows/checks.yml`, which runs on every PR and on pushes to `main`/`master`:
- **`scripts` job:** shellcheck (pinned and checksummed) over the hooks and scripts, then `sh scripts/test/run-all.sh`.
- **`procedure` job:** `scripts/ci-checks.sh` / `scripts/ci-pr-checks.sh`. These check for placeholders, secrets, task IDs and the `/docs` consensus trailer.
- **App tests (T-004)** run in the `scripts` job, after the gate suites: `actions/setup-node` pinned by commit SHA (v7.1.0), Node **22.9.0** (the `engines` floor), its package cache **off** (a cache shared between PR and `main` runs could be poisoned), then `npm ci --ignore-scripts` and `npm test`. They sit in that job on purpose: its check is required, and a new job or a matrix would not be (a matrix renames the check). Which Node version production runs is T-006. The CI pin and the `engines` floor move together: a Node upgrade bumps both. setup-node downloads the Node binary **without a pinned checksum** (unlike shellcheck); the action itself is pinned by SHA.
- **Branch protection (confirmed 2026-11-18).** The ruleset `protection-main` is active on the default branch. Read through the GitHub API (`repos/V3rilen/glucoscope/rulesets`) after the owner set it up. It:
  - requires both checks, `shell scripts (lint + test)` and `procedure checks`, from the GitHub Actions app, and the branch must be up to date before merging
  - requires a pull request (0 approvals, since the owner is the only reviewer)
  - blocks force-pushes and branch deletion
  - has an empty bypass list
- **Limit:** a PR runs its **own** `checks.yml`, so a PR could remove the `npm test` step and still pass. The gate scripts are protected (`ci-pr-checks.sh` runs the target branch's copy); this step is not. Today's controls are that a `.github/` change is Risky tier and named in the PR summary (`AGENTS.md` § 8), and the owner's review. That review is a self-review in practice (the owner merges their own PRs with 0 required approvals). A mechanical check is [T-008](../tasks/T-008.md).

### Release and rollback
- **How a release reaches production, the process manager, the `cloudflared` setup, where logs go, DB backups (`pg_dump` off-machine, test-restored; planned in `PROJECT_PLAN.md` § 8), and rollback:** all `UNKNOWN — needs human confirmation`, tracked in **[T-006](../tasks/T-006.md)**.
- **Owner decision (2026-11-17, `tasks/T-001.md`): no production deploy until T-006 lands.** T-006 depends on **[T-005](../tasks/T-005.md)**, because whether migrations can be reversed determines how a release can be rolled back.
- Rollback for today's code (no schema) would be redeploying the previous commit. That is not tested, so it is not claimed as the procedure.

## 8. Verification

Checked on 2026-11-17: components from `git ls-files` (excluding `node_modules`); request flow and middleware from `src/app.js` line by line; failure modes from `src/models/db.js`, `src/controllers/homeController.js`, `src/middleware/errorHandler.js` and `server.js`; pool defaults from `node_modules/pg-pool/index.js`; versions and licenses from `package-lock.json` (81 packages counted by script); CI from `.github/workflows/checks.yml` and `scripts/test/run-all.sh`; owner decisions from `PROJECT_PLAN.md` (§ 2–3 and § 7–9 "decided"; § 11 "decided for now, open to change"). Reviewers re-checked these claims against the source (`tasks/T-001.5.md`). **T-004 (2026-11-18):** § 6 was rewritten from the files in `test/` and `package.json`, and checked by running `npm test` (41 tests after the build review, 0 failures, three runs in a row, and again with `NODE_ENV=production` and an unreachable `DATABASE_URL` set in the shell). A test that forgets to fake the database was shown to fail. The CI step was checked against `scripts/test/test-ci-wiring.sh`. The setup-node commit was checked to be the commit tag `v7.1.0` points to, and part of `actions/setup-node`'s own history.

---

**Update this doc when** any of these change: the files or directories under `src/`, `server.js`, `views/` layout structure, `public/`; `package.json` dependencies, engines or scripts; `package-lock.json` major versions or new licenses; `.github/workflows/**`; `test/setup.js`, `test/helpers/**` or the `npm test` script; the GitHub ruleset; deployment, Cloudflare, process manager, backup or rollback (T-006); a new trust boundary (for example `/api/v1/*`, which needs a threat model first); or a decision recorded in `docs/decisions/`.
