# Data Model — Glucoscope

> **Status: descriptive. There are no application tables.** PostgreSQL is a real datastore (the app holds a connection pool), but no schema, migration or SQL file exists yet. § 4 lists the owner's planned data rules, labelled **planned**. The draft schema is linked, not copied, because the owner has marked it *proposed*.

## 1. Datastore

| Item | Value | Source |
|---|---|---|
| Engine | PostgreSQL | `PROJECT_PLAN.md` § 2; `pg` dependency |
| Driver | `pg` 8.23.1 (`pg-pool` 3.14.0) | `package-lock.json` |
| Connection | one module-level `pg.Pool`, created when `src/models/db.js` is imported | `src/models/db.js:3` |
| Config | `connectionString: process.env.DATABASE_URL` only. Other fields come from `PG*` env vars or pg defaults. | `contracts.md` § 7 |
| Pool settings | pg-pool defaults: `max` 10, `idleTimeoutMillis` 10000, **no `connectionTimeoutMillis`**, no explicit `ssl` | `node_modules/pg-pool/index.js:89,98-99` |
| Lifecycle | connects lazily on first query; `error` listener logs idle-client errors; **never ended** (no shutdown hook) | `db.js:5-8`; `server.js` |
| PostgreSQL server version | `UNKNOWN — needs human confirmation` (T-005) | — |
| DB role and privileges | Plan: dedicated non-superuser app role, localhost only (`PROJECT_PLAN.md` § 8). Actual: `UNKNOWN` (T-006). `.env.example` names a role `glucoscope_app` and a database `glucoscope` as example values only. | `.env.example` |
| Backups | Plan: scheduled `pg_dump`, stored off the machine, test-restored. Actual: `UNKNOWN` (T-006). | `PROJECT_PLAN.md` § 8 |

## 2. Tables

**None.** The only SQL the app runs is `SELECT 1` in `checkConnection()` (`src/models/db.js:17`).

Session storage (`connect-pg-simple`'s `session` table) is planned but not installed.

## 3. Query access rules (in code today)

- All SQL goes through `query(text, params?)` in `src/models/db.js`, which passes it to `pool.query`.
- **Values must be passed as `$1`-style parameters, never concatenated into SQL text** (`db.js:10`; `contracts.md` § 9 I4).
- `query` lets errors propagate, so they reach the global error handler and render a 500 page. Model functions may catch errors and return consistent empty results where that is the right behaviour; this pattern is allowed by the course rubric and recorded in `PROJECT_PLAN.md` § 9.
- `checkConnection()` is the one function that swallows errors: it returns `false` and logs `err.message`.

## 4. Planned data rules (owner decisions, not yet in code)

From `PROJECT_PLAN.md` § 9 ("decided"):
- Glucose is stored as **integer mg/dL**. Units are converted only for display.
- Times are stored as **`TIMESTAMPTZ`** and rendered in the user's time zone.
- Index on `(user_id, reading_time)`. Expected volume is about 288 CGM readings per user per day.
- Duplicate xDrip+ uploads are dropped with a unique `(user_id, reading_time)` constraint for CGM readings plus `ON CONFLICT DO NOTHING` (§ 7).
- Manual readings use `source = 'manual'` and can be edited. CGM data is read-only (§ 6).
- Deleting an account removes its health data through `CASCADE` (§ 3).

The **draft table list** with planned `CASCADE` / `SET NULL` choices is in [`PROJECT_PLAN.md` § 10](../PROJECT_PLAN.md), which the owner marks **proposed**. It is not a contract. When a table is created, it moves into § 2 of this file, along with its columns, types, indexes, foreign keys, PII classification and consumers.

## 5. PII and health-data classification

- **No columns exist, so no PII is stored yet.**
- Planned glucose readings, manual entries and day comments are **health data**, classified **sensitive** (see `architecture.md` § 2, owned by the Architect). Planned rule: admins never read them (`PROJECT_PLAN.md` § 3).
- Planned account data (email, password hash, upload-secret hash) is PII or credentials.

## 6. How to change the schema safely

The tooling is **`UNKNOWN — needs human confirmation`**: no migration tool, directory layout, naming convention, reversibility rule or deploy sequencing has been chosen. **[T-005](../tasks/T-005.md)** decides these before the first table is created. The owner's folder structure (`PROJECT_PLAN.md` § 13, "Folder structure (decided …)") lists `database/` holding `schema.sql` and `seed.sql`. T-005 confirms or replaces that layout and adds the rules it doesn't cover: versioning, reversibility and deploy sequencing.

Until T-005 lands, these rules apply. They come from `AGENTS.md` and the code:
1. The first table is a **Risky-tier** change (schema work, `AGENTS.md` § 5) and needs the Data Engineer's review.
2. Every new table or column is added to § 2 of this file in the same pull request, with its PII classification and consumers.
3. SQL uses parameters only (§ 3).

## 7. Verification

Checked on 2026-11-17:
- `find . -path ./node_modules -prune -o -name '*.sql' -print` returned nothing.
- Grep for `CREATE TABLE`, `migrat` and `schema` outside `node_modules` matched only docs, task and agent markdown.
- No `database/` or `migrations/` directory exists.
- Grep for SQL in `src/` found only `SELECT 1` (`db.js:17`).
- Pool defaults were read from `node_modules/pg-pool/index.js`.

The Data Engineer re-checked these claims against the repo (`tasks/T-001.5.md`).

---

**Update this doc when** any of these change: `src/models/**`; any file containing SQL; any migration, schema or seed file (including a future `database/` directory); the pool configuration or `DATABASE_URL` handling; the addition of `connect-pg-simple` or any other library that creates tables; T-005's choice of migration tooling; or the backup and role setup (T-006).
