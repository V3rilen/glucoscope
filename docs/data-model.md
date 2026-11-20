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
| PostgreSQL server version | **Target: PostgreSQL 17** ([ADR 0002](./decisions/0002-database-migrations.md) § 8). The owner's dev container (`postgres:17` image, on the unmerged `wip/database-setup` branch) reported `17.11` on 2026-11-19. T-009 pins the minor version in compose and CI. Production: `UNKNOWN` (T-006). | `postgres --version` in the container, 2026-11-19 |
| DB role and privileges | **Decided** (ADR 0002 § 11, built in T-011): `glucoscope_owner` owns the schema and runs the `db:*` scripts; `glucoscope_app` serves requests with `SELECT`/`INSERT`/`UPDATE`/`DELETE` only. On the server: `UNKNOWN` (T-006). `.env.example` names a role `glucoscope_app` and a database `glucoscope` as example values only. | `.env.example` |
| Backups | **Decided** (ADR 0002 § 6, built in T-010): `db:migrate` takes a full `pg_dump` before applying pending migrations, and keeps the newest 5 in `BACKUP_DIR`. Scheduled off-machine backups are planned in `PROJECT_PLAN.md` § 8. Actual: `UNKNOWN` (T-006). | `PROJECT_PLAN.md` § 8; ADR 0002 |

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
- **Backup files** (ADR 0002 § 6, planned and built in T-010) hold every table, so they hold all PII, credentials and health data. They are classified **sensitive** and stored as follows:
  - **Location:** `BACKUP_DIR`, outside the repo and not under `/tmp`. The directory has mode 700.
  - **Files:** mode 600, never logged.
  - **Retention:** the newest 5 are kept.
  - **Privacy note:** a deleted account's data stays in backups until the newest 5 have rotated past it.
- **Database errors must not reach the logs with values in them.** Invariant I9 (`contracts.md` § 9) is planned now and becomes binding in T-011.

## 6. How to change the schema safely

**Decided in [ADR 0002](./decisions/0002-database-migrations.md) (T-005, 2026-11-20). Built by T-009, T-010 and T-011.** None of it exists in code yet. Until T-009 lands, there is no runner, and **no table may be created** (ADR 0002, Follow-ups: T-009 blocks schema v1; `tasks/T-005.md`, the dependency table).

### Rules
1. **One migration per change:** `database/migrations/NNNN_short_snake_name.sql`.
   - The number has four digits, is sequential, and is never reused.
   - Apply it with `npm run db:migrate`, never on app startup.
   - An applied file is **never edited**, because the runner checks its SHA-256 against `schema_migrations`.
2. **Forward-only.**
   - Fix a mistake with a new migration.
   - Changes follow expand-then-contract, so the previous release still runs on the new schema.
   - The default rollback is the app, not the database.
3. **The Data Engineer redlines apply to every migration:**
   - no destructive change without a deprecation plan and a forward fix,
   - no `NOT NULL` on a populated column without a tested backfill,
   - no foreign-key column without an index.
4. **Markers.**
   - A destructive file starts with `-- migrate:destructive`, and running it needs `--confirm-destructive`.
   - A file that cannot run inside a transaction (for example `CREATE INDEX CONCURRENTLY`) starts with `-- migrate:no-transaction` and holds one statement.
   - Either marker makes the change Risky tier with Data Engineer sign-off.
5. **Backfills.**
   - A backfill runs inside the migration's transaction, except on `glucose_readings` and `events`. On those two tables it runs as batched updates outside the transaction, with a progress check and Data Engineer review.
   - Migrations never depend on rows from `seed.sql`.
6. **Seed data.**
   - **`database/seed.sql`** holds the default data. It runs everywhere through `npm run db:seed` and is safe to rerun.
   - **`database/seed-test.sql`** holds test accounts and sample data. It runs only in development and test, through `db:seed --test`.
   - Code looks reference rows up **by name, never by ID**.
7. **Deploy order:** `db:migrate` (which takes a backup first, from T-010), then `db:seed`, then restart the app.
8. **Recovery.**
   - `npm run db:restore -- --file <name> --yes` restores the backup taken before the migration (T-010).
   - Data written after that backup is lost. The owner accepted this on 2026-11-20 (`tasks/T-005.md`).
9. **Every new table or column** is added to § 2 of this file in the same pull request, with its PII classification and consumers.
10. **SQL uses parameters only** (§ 3).

### Not built yet

| Piece | Task | Blocks |
|---|---|---|
| Runner, `seed.sql`/`seed-test.sql`, `db:reset`, test database, CI Postgres | T-009 | schema v1 |
| Backup before migrating, `db:restore` | T-010 | T-006 (any production deploy) |
| Owner/app role split, logging invariant I9 | T-011 | T-006, and any upload of real glucose data |

### Planned exception
`connect-pg-simple`'s `session` table uses `timestamp(6)` without a time zone. This exception is required by the library, and it will be recorded in § 2 when the table lands (ADR 0002 § 9).

## 7. Verification

Checked on 2026-11-17:
- `find . -path ./node_modules -prune -o -name '*.sql' -print` returned nothing.
- Grep for `CREATE TABLE`, `migrat` and `schema` outside `node_modules` matched only docs, task and agent markdown.
- No `database/` or `migrations/` directory exists.
- Grep for SQL in `src/` found only `SELECT 1` (`db.js:17`).
- Pool defaults were read from `node_modules/pg-pool/index.js`.

The Data Engineer re-checked these claims against the repo (`tasks/T-001.5.md`).

**T-005 (2026-11-20):** § 1, § 5 and § 6 were rewritten from ADR 0002.
- The claims "no SQL file and no `database/` or `migrations/` directory on `main`" were re-checked on branch `chore/migration-tooling` with `git ls-files`.
- The PostgreSQL version was read with `postgres --version` inside the owner's dev container.
- The `glucose_readings` growth figure (288 readings a day per user, about 105k a year) comes from `PROJECT_PLAN.md` § 9.

---

**Update this doc when** any of these change: `src/models/**`; any file containing SQL; any migration, schema or seed file (`database/**`); the pool configuration or `DATABASE_URL`/`MIGRATION_DATABASE_URL` handling; the addition of `connect-pg-simple` or any other library that creates tables; ADR 0002 or its build tasks (T-009, T-010, T-011); or the backup and role setup on the server (T-006).
