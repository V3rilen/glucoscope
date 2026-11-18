# Contracts — Glucoscope

> **Status: descriptive.** This file lists what exists in the code on branch `chore/docs-bootstrap` (base `main` @ `49c38a5`). The one forward-looking section is § 12, and it is labelled as such. Anything not confirmed by the code or by the owner is written `UNKNOWN — needs human confirmation`.
>
> **How to use it.** Before you add, change or remove anything listed here, find its entry. If your change alters an entry, it is a **contract change** (`AGENTS.md` § 7 step 8): update this file in the same pull request, state the blast radius, and keep it backward-compatible or document a migration path. If you find a contract in the code that is not listed here, that is a gap. Surface it.
>
> **Test coverage today.** No automated test guards any entry in this file. Every "Guarded by" field reads `none — T-004`. Until [T-004](../tasks/T-004.md) lands, the regression-safety step "run the tests that exercise the touched contracts" cannot be met, and feature work is blocked (`tasks/T-001.md`, owner decision 2026-11-17).

## 1. Routes and endpoints

Every request goes through the middleware chain in § 2 in order. There are exactly two application routes, both in `src/routes/index.js`. No route requires authentication, because the app has no authentication yet (§ 10).

| # | Method | Path | Auth | Handler | Success response | Other responses |
|---|---|---|---|---|---|---|
| R1 | `GET` (and `HEAD`, which Express answers automatically from a `GET` route) | `/` | none | `showHome`, `src/controllers/homeController.js:3-5` | `200`, HTML, renders `pages/home` with `{ title: 'Home' }` | Render failure → error handler, 500 (§ 3.3) |
| R2 | `GET` (and `HEAD`) | `/health` | none, public on purpose | `showHealth`, `src/controllers/homeController.js:7-10` | `200`, `application/json`, body exactly `{"status":"ok"}` | `503`, body exactly `{"status":"unavailable"}` when `checkConnection()` returns `false` |
| R3 | `GET`, `HEAD` | any path that matches a file under `public/`, served **at the site root**. Today the only file is `public/css/styles.css` → `/css/styles.css` | none | `express.static(path.join(rootDir, 'public'))`, `src/app.js:32`, default options | `200` with the file and serve-static's default `Cache-Control: public, max-age=0` | A directory path without a trailing slash redirects (`GET /css` → `301 Location: /css/`, no `no-store`), and `/css/` then gives R5 (404). A miss falls through to the next middleware, which leads to R5. |
| R4 | `OPTIONS` | `/`, `/health` | none | the router's automatic `OPTIONS` responder (Express 5 `router` package) | `200`, `text/plain`, body `GET, HEAD`, header `Allow: GET, HEAD`, plus `no-store` (M7) | — |
| R5 | any other | anything R1–R4 do not answer, including other methods on `/` and `/health` (for example `POST /`) | none | `notFound` then `errorHandler`, `src/middleware/errorHandler.js` | n/a | `404` HTML error page (§ 3.3). Express 5 sends no `405`. |

**R1, invariant:** `GET /` renders HTML with status 200 and needs no database. **Blast radius:** the header brand link and the "Home" nav link (`views/partials/header.liquid:3,5`) and the "Back to home" link on the error page (`views/pages/error.liquid:5`) all point here. **Guarded by:** none — T-004.

**R2, invariant:** the path stays `/health`. The status is `200` only when `SELECT 1` succeeds, otherwise `503`. The body is `{"status":"ok"|"unavailable"}` and never includes error details. It runs one database query per request. **Known gap:** the pool sets no `connectionTimeoutMillis` (§ 6). A refused connection fails fast and returns 503. An **unreachable** host makes `/health` wait until the operating system's TCP connect timeout expires, which depends on the OS and is on the order of minutes on Linux. Only then does it return 503. Cloudflare may give up with its own timeout first. While this happens, requests beyond the pool's 10 connections queue with no limit. `PGCONNECT_TIMEOUT` does **not** help (§ 7.2). The fix belongs to T-006. **Blast radius:** `README.md` documents the 200/503 behaviour. Any uptime monitor pointed at it is `UNKNOWN — needs human confirmation` (T-006). **Guarded by:** none — T-004.

**R3, invariant:** static files are served at the root, not under `/public`. Static responses are sent **before** the `Cache-Control` middleware and the form parser, so they do **not** carry `Cache-Control: private, no-store` (§ 2). Nothing with user data may ever be put in `public/`. **Blast radius:** `views/layouts/main.liquid:7` links `/css/styles.css`. Moving the mount or the file breaks every page's styling. **Guarded by:** none — T-004.

**R4, invariant:** `OPTIONS` on a defined route is answered by the router, not by app code, and reveals only the allowed methods. **Guarded by:** none — T-004.

**R5, invariant:** unmatched requests get an HTML 404 through the global error handler, never Express's default page. **Guarded by:** none — T-004.

Verified by running the app on 2026-11-17 (`OPTIONS /` → 200 `Allow: GET, HEAD`; `GET /css` → 301 `/css/`; `GET /css/styles.css` → `Cache-Control: public, max-age=0`; `POST /` and `GET /nope` → 404 with `private, no-store`; no `X-Powered-By` on any of them).

## 2. Global middleware chain (order is a contract)

From `src/app.js`. The order matters. Each layer applies only to requests that reach it.

| # | Line | Middleware / setting | Invariant | Breaks if changed |
|---|---|---|---|---|
| M1 | 22–24 | LiquidJS registered as the `liquid` view engine, views root `views/` | `res.render('pages/x')` resolves to `views/pages/x.liquid` | Every `res.render` call (R1, error handler) |
| M2 | 25 | `app.disable('x-powered-by')` | No `X-Powered-By` header on any response | Small information leak if removed |
| M3 | 26 | `app.locals.siteName = 'Glucoscope'` | Every template gets `siteName` | Layout `<title>`, header, footer, home page (§ 4) |
| M4 | 30 | `trust proxy = 1`, **only when `NODE_ENV === 'production'`** | In production `req.ip`, `req.protocol` and `req.secure` come from the first proxy hop (Cloudflare or `cloudflared`). In any other environment they don't. | Nothing reads `req.ip`, `req.protocol` or `req.secure` today. Future secure cookies and rate limiting will depend on this. The comment at `src/app.js:28-29` describes that future need; **no sessions exist yet.** |
| M5 | 32 | `express.static(public/)` | R3. Runs before M6 and M7. | Static files would start getting `no-store` if moved below M7 |
| M6 | 33 | `express.urlencoded({ extended: false })` | Parses `application/x-www-form-urlencoded` bodies into `req.body`, using Express 5 / body-parser defaults (100 kb limit). A malformed or oversized body raises an error with a 4xx status, which renders the error page (§ 3.3). | Future form handlers. No handler reads `req.body` today. |
| M7 | 36–39 | sets `Cache-Control: private, no-store` | **Every response that reaches this point** (R1, R2, R4 and R5, including error pages) carries `Cache-Control: private, no-store`, so neither Cloudflare nor browsers store pages that may contain health data | Health data could be cached by Cloudflare or a shared browser. Security invariant (§ 9 I3). |
| M8 | 41 | `app.use(routes)` | Mounts R1 and R2 | — |
| M9 | 43 | `notFound` | Turns any request that reaches it into a 404 error | R5 |
| M10 | 44 | `errorHandler` | Must be last, and must keep exactly **four** parameters (`src/middleware/errorHandler.js:13-14`). Express recognizes an error handler by its arity. | With 3 parameters Express treats it as normal middleware: errors would reach Express's default handler and could leak stack traces |

Not present: no JSON body parser (`express.json`), no session, cookie, CSRF, CORS, compression, security-header (CSP/HSTS), logging or rate-limit middleware. **Guarded by:** none — T-004.

## 3. Request and response contracts

### 3.1 HTML pages (R1)
`Content-Type: text/html; charset=utf-8`. The page is the `main` layout (§ 4) wrapping `pages/home`. Headers include `Cache-Control: private, no-store` (M7) and no `X-Powered-By` (M2).

### 3.2 `/health` (R2)
`Content-Type: application/json; charset=utf-8`. Body `{"status":"ok"}` (200) or `{"status":"unavailable"}` (503). This is the only JSON response in the app.

### 3.3 Error responses (R5 and any thrown or rejected error) — `src/middleware/errorHandler.js`
- **Always HTML.** It renders `pages/error` even for a JSON route such as `/health`. A future JSON API (§ 12) must add its own error handling or extend this one, and that would be a contract change.
- **Status:** `err.status` if it is from 400 to 599, otherwise `500` (line 17).
- **Logging:** only status ≥ 500 errors are logged, as the full error object via `console.error` (line 18).
- **Already-started responses:** if `res.headersSent`, it delegates to Express's default handler (line 15).
- **If `pages/error` itself fails to render**, the render error goes to Express's built-in final handler. That handler prints a stack trace whenever `NODE_ENV` is not `production` (another reason for I1).
- **Titles:** `"Page not found"` for 404, otherwise `"Error"` (line 21). The heading renders as `{{ status }}: {{ title }}`.
- **Public messages, exactly** (lines 7–11):
  - 404 → `We couldn't find that page.`
  - other < 500 → `That request couldn't be processed.`
  - ≥ 500 → `Something went wrong on our end. Please try again.`
- The page always includes a **"Back to home"** link to `/` (`views/pages/error.liquid:5`).
- **Stack traces:** `stack` is `null` when `NODE_ENV === 'production'`, otherwise `err.stack`, which renders in `<pre class="error-stack">` (line 24, `error.liquid:6-8`). The 404 error's message includes `req.originalUrl`, so in development a user-supplied URL is echoed back inside the stack. That is safe only because of output escaping (§ 9 I2).

**Invariant:** no internal detail (stack, SQL, error message) reaches the client in production. **Guarded by:** none — T-004.

## 4. View and template contracts

Configured at `src/app.js:11-18`: root `views/`, layouts `views/layouts/`, partials `views/partials/`, extension `.liquid`, `outputEscape: 'escape'`, and `cache` on only in production.

| Template | Kind | Variables it reads | Set by |
|---|---|---|---|
| `views/layouts/main.liquid` | layout `main`, defines block `content` | `title`, `siteName` | each page's render locals and `app.locals` |
| `views/pages/home.liquid` | page (`{% layout 'main' %}`) | `siteName` | `app.locals` |
| `views/pages/error.liquid` | page | `status`, `title`, `message`, `stack` | `errorHandler` |
| `views/partials/header.liquid` | partial, included with `{% render %}` | `siteName` (passed explicitly) | `main.liquid:10` |
| `views/partials/footer.liquid` | partial, included with `{% render %}` | `siteName` (passed explicitly) | `main.liquid:14` |

**Invariants**
- Every page sets `title` and uses `{% layout 'main' %}` with `{% block content %}`. The browser tab reads `{{ title }} | {{ siteName }}`.
- Partials are included with `render`, which **isolates scope**: a partial sees only the variables passed to it (today just `siteName`). Adding a variable to a partial means passing it explicitly in `main.liquid`.
- `outputEscape: 'escape'` HTML-escapes every `{{ }}` output by default (§ 9 I2).
- Page-level user-facing text: `<html lang="en">`; `<nav aria-label="Main">` with one link, "Home"; the footer disclaimer "*{{ siteName }} displays glucose data for information only and is not a medical device.*" (`footer.liquid:3`).

**CSS class coupling** (`public/css/styles.css` ↔ templates): `container` (`main.container`, header, footer), `site-header`, `site-header__inner`, `site-header__brand`, `site-footer`, `lead`, `error-stack`. Renaming one on either side silently drops its styling.

**Guarded by:** none — T-004.

## 5. Public interfaces — exported module signatures

| Module | Export | Signature and behaviour | Callers (blast radius) |
|---|---|---|---|
| `src/app.js` | `default` | The configured Express app. **Does not call `listen`**, so it can be imported by tests. | `server.js:1`. T-004 tests will import it. |
| `src/routes/index.js` | `default` | An Express `Router` with R1 and R2 | `src/app.js:4,41` |
| `src/controllers/homeController.js` | `showHome(req, res)` | Renders `pages/home` | `src/routes/index.js:6` |
| | `showHealth(req, res)` → `Promise<void>` | Async. Awaits `checkConnection()`, which never rejects. | `src/routes/index.js:7` |
| `src/middleware/errorHandler.js` | `notFound(req, res, next)` | Calls `next(err)` with `err.status = 404`, message `Not found: <originalUrl>` | `src/app.js:43` |
| | `errorHandler(err, req, res, next)` | § 3.3. **Must keep 4 parameters.** | `src/app.js:44` |
| `src/models/db.js` | `query(text, params?)` → `Promise<pg.QueryResult>` | Thin pass-through to `pool.query`. `params` is optional. **Errors propagate** to the caller and so to the global error handler. Values must always be passed as `$1`-style parameters, never concatenated into `text` (comment at line 10; § 9 I4). | No callers yet |
| | `checkConnection()` → `Promise<boolean>` | Runs `SELECT 1`. Returns `true` or `false` and **never throws**. On failure it logs `err.message` only. | `src/controllers/homeController.js:8` |

**Guarded by** (every export in this table): none — T-004.

**Import side effect:** importing `src/models/db.js` immediately creates the `pg.Pool` (line 3) and attaches an `error` listener (lines 6–8). Connections open lazily, on the first query. `pool.end()` is never called, and there is no shutdown hook in `server.js`.

`server.js` is the process entry point. It exports nothing.

## 6. Data contracts

PostgreSQL is the only datastore, reached through `src/models/db.js`. **There are no application tables, migrations or SQL files** (verified, see `data-model.md`). The only SQL the app runs is `SELECT 1` (`db.js:17`).

Pool configuration: only `connectionString` is set. Everything else uses the `pg` 8.23.1 / `pg-pool` 3.14.0 defaults: `max` 10 (`node_modules/pg-pool/index.js:89`), `idleTimeoutMillis` 10000 (`pg-pool/index.js:98-99`), **no `connectionTimeoutMillis`**, and no explicit SSL (§ 7).

Table-level contracts and the planned schema: see [`data-model.md`](./data-model.md).

## 7. Environment variables and configuration

The app reads env vars through `process.env`. `npm start` and `npm run dev` load `.env` if it exists (`--env-file-if-exists`, `package.json:12-13`). `.env` is gitignored (`.gitignore`), and `.env.example` is the committed template.

### 7.1 Read directly by app code

| Var | Read at | Required? | Default | Controls | Secret? |
|---|---|---|---|---|---|
| `NODE_ENV` | `src/app.js:9`, `src/middleware/errorHandler.js:24` | Must be `production` in production (§ 9 I1) | unset, which behaves as "not production" | **Security-relevant.** If it is anything other than exactly `production` (including unset or `prod`): stack traces render on error pages, `trust proxy` is off, and the Liquid template cache is off | no |
| `PORT` | `server.js:3` | optional | `3000` | Listening port | no |
| `DATABASE_URL` | `src/models/db.js:3` | Effectively required. If unset, `pg` falls back to the `PG*` vars and its own defaults (localhost:5432, OS user) | none | PostgreSQL connection string | **yes**, it contains the DB password |

`.env.example` lists exactly these three. **Guarded by:** `NODE_ENV`: none — T-004 (production-mode cases). `PORT`, `DATABASE_URL`: none — T-004.

### 7.2 Read implicitly by `pg` (not referenced in app code, but they change behaviour)
From `node_modules/pg/lib/connection-parameters.js` and `defaults.js` (pg 8.23.1). If `DATABASE_URL` is set, its values take precedence. These vars fill only the fields the URL leaves out (`connection-parameters.js:59-61, 9-23`).

| Var | Fills | Note |
|---|---|---|
| `PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD`, `PGDATABASE` | host, port, user, password, database | `PGPASSWORD` is a secret. If no database is given, it defaults to the user name. |
| `PGSSLMODE` | SSL (`disable` → off; `prefer`/`require`/`verify-ca`/`verify-full` → on; `no-verify` → on without cert verification) | Read only when the config gives no `ssl`. Today nothing sets SSL, so this var decides it. |
| `PGSSLNEGOTIATION`, `PGOPTIONS`, `PGCLIENT_ENCODING`, `PGREPLICATION`, `PGAPPNAME` | the matching connection parameters | — |
| `PGCONNECT_TIMEOUT`, `PGBINARY` | read into `ConnectionParameters`, but **no effect on the pure-JS client this app uses** | `connect_timeout` is used only in `getLibpqConnectionString` (`connection-parameters.js:143-150`), which only the native client calls (`pg/lib/native/client.js:98`), and `pg-native` is not installed. The JS client's connect timeout comes only from `connectionTimeoutMillis` (`client.js:116`). `binary` comes from the config object, not the env (`client.js:102`). |
| `USER` (or `USERNAME` on Windows) | default user | `defaults.js:5` |
| `PGPASSFILE` / `~/.pgpass` | password, when none is given | Through the `pgpass` module, which pg marks deprecated (`node_modules/pg/lib/client.js:25-26, 299`) |

### 7.3 Package and runtime contracts (`package.json`)
- `"type": "module"`: ESM only. `require` is not allowed (course rubric, `PROJECT_PLAN.md` § 2).
- `"engines": { "node": ">=22.9.0" }`: needed for `--env-file-if-exists` (added in Node 22.9.0) and `import.meta.dirname` (`src/app.js:7`).
- Scripts: `start` = `node --env-file-if-exists=.env server.js`; `dev` = `node --watch --env-file-if-exists=.env server.js`. There is **no `test` script** (T-004).
- Runtime dependencies (exact versions from `package-lock.json`): `express` 5.3.0, `liquidjs` 10.30.1, `pg` 8.23.1. See `architecture.md` § Stack.

### 7.4 Feature flags
**None.** Verified by grep: there is no flag library and no env var or config key used as a toggle. `NODE_ENV` is an environment switch, not a feature flag.

## 8. Integrations, events, scheduled jobs

| Category | Inventory |
|---|---|
| Third-party integrations called by code | **PostgreSQL only** (`src/models/db.js`). Failure: `query` rejects, which leads to a 500 error page, and `checkConnection` returns `false`, which leads to a `/health` 503. Timeout: none configured (§ 6). |
| Infrastructure in the request path, not called by code | **Cloudflare**, the owner's decision in `PROJECT_PLAN.md` § 8. The app's only coupling is M4 (`trust proxy`) and M7 (`no-store`). How the origin is connected and its SSL mode are `UNKNOWN — needs human confirmation` (T-006). |
| Events, queues, webhooks published or consumed | **None** (grep finds no emitter, queue or webhook code) |
| Scheduled jobs and cron | **None** in the repo. DB backups (`pg_dump`) are planned in `PROJECT_PLAN.md` § 8 but do not exist (T-006). |
| Outbound HTTP calls | **None** |

## 9. Cross-cutting invariants

| # | Invariant | Where | What breaks if violated | Guarded by |
|---|---|---|---|---|
| I1 | Production runs with `NODE_ENV` exactly `production` | § 7.1 | Stack traces reach users (from the app's error handler and from Express's final handler), `trust proxy` is off (future secure cookies won't set), templates are recompiled on every render | none — T-004 (code side); the server setting — T-006 |
| I2 | Template output is HTML-escaped by default (`outputEscape: 'escape'`). Never output user content with `| raw`. | `src/app.js:16` | XSS, including through the development stack trace, which echoes the request URL | none — T-004 |
| I3 | Every non-static response carries `Cache-Control: private, no-store`, and static files are never user-specific | M5, M7 | Health data cached at Cloudflare or in a browser | none — T-004 |
| I4 | SQL values are passed only as `$n` parameters, never string-concatenated | `src/models/db.js:10` | SQL injection | review only (no SQL yet beyond `SELECT 1`) |
| I5 | The error handler stays last and keeps 4 parameters | M10 | Express's default error page, which may leak detail | none — T-004 |
| I6 | `src/app.js` never calls `listen`; only `server.js` does | § 5 | Tests could no longer import the app without opening a port | none — T-004 (its tests import the app) |
| I7 | No secret is committed. Secrets live only in `.env` (gitignored). | `.gitignore`, `.githooks/pre-commit`, `scripts/ci-checks.sh` | Credential leak | the secret scan in the pre-commit hook and CI (`scripts/test/test-pre-commit.sh`, `test-ci-checks.sh`) |
| I8 | Glucose and other health data is never sent to an admin view (owner decision, `PROJECT_PLAN.md` § 3) | Planned. No data exists yet. | Privacy breach. Becomes a code-level contract when the first data route lands. | n/a until built |

## 10. Absent today (recorded as fact so no one assumes otherwise)

There is no authentication, no sessions, no roles, no CSRF protection, no input validation, no rate limiting, no security headers beyond M2 and M7 (no CSP, no HSTS), no JSON body parser, no request logging, no graceful shutdown, no `npm audit` or dependency scan in CI, no application tests, no migrations, and no deployment configuration in the repo. `express-session`, `bcrypt` and `connect-pg-simple` are **decided but not installed** (`PROJECT_PLAN.md` § 2, ADR 0001).

## 11. Verification

How this inventory was built (2026-11-17):
- **Routes:** read `src/routes/index.js` and every `app.use` / `app.set` / `app.engine` / `app.disable` in `src/app.js`. Grepped `src/` and `server.js` for `router.`, `app.`, `Router(` and `.use(`. No other mounts exist.
- **Env vars:** grepped `server.js`, `src/` and `views/` for `process.env`. `pg`'s implicit vars were read from `node_modules/pg/lib/connection-parameters.js`, `defaults.js`, `client.js` and `node_modules/pgpass/lib/helper.js`.
- **Exports:** grepped `src/` for `export`. Pool defaults were read from `node_modules/pg-pool/index.js`.
- **Templates and CSS:** read every file in `views/` and grepped `public/css/styles.css` for class selectors.
- **Absences:** checked for `**/*.sql`, `CREATE TABLE`, `cron`, `EventEmitter`, `fetch(` and flag patterns outside `node_modules`. None found.
- **Versions and licenses:** read `package-lock.json`.
- **Runtime behaviour:** started the app on a random port and sent `OPTIONS /`, `OPTIONS /health`, `GET /css`, `GET /css/styles.css`, `POST /` and `GET /nope`, checking status, `Cache-Control`, `Allow`, `Location` and `X-Powered-By` (results under § 1). `pg` timeout behaviour was checked in `node_modules/pg/lib/client.js:116` and `connection-parameters.js:143-150`.
- The five reviewers re-checked these claims against the source in the T-001 build review (`tasks/T-001.5.md`).

---

**Update this doc when** any of these change: `src/app.js`, `src/routes/**`, `src/controllers/**`, `src/middleware/**`, `src/models/**`, `server.js`, `views/**`, the class names in `public/css/**`, any file added to `public/`, `package.json` (scripts, engines, type, dependencies), `.env.example`, any new `process.env` read, any new SQL, table or migration, any new outbound call, job, event or flag, or the Cloudflare or origin setup. A change to a contract and the update to this file belong in one pull request (`AGENTS.md` § 8).
