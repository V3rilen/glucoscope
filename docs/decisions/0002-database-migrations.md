# 0002 — Database migrations, seed data, backups and test database

- **Status:** accepted
- **Date:** 2026-11-20
- **Deciders:** the owner, who approved the plan in session on 2026-11-20 (`tasks/T-005.md`, activity log), and the five reviewing agents plus the Review Coordinator (`tasks/T-005.md` § Review).
- **Task:** T-005. Built by T-009, T-010 and T-011.

## Context
No table exists yet (`data-model.md` § 2). The owner decided that T-005 must land before the first table is created (`PROJECT_PLAN.md` § 13, 2026-11-17). The owner's unmerged branch `wip/database-setup` holds:
- a Docker PostgreSQL 17 setup,
- a single non-superuser role `glucoscope_app` that owns the `public` schema,
- `database/schema.sql` (11 app tables plus `session`), `database/seed.sql`,
- `database/setup.js`, which applies the schema once or drops and reapplies it.

That approach only works on an empty database. Once there are accounts and readings, the schema has to change without losing data, and every database (dev, test, production) has to end up with the same changes.

Three security facts shape this decision:
1. PostgreSQL error messages repeat input values. For example, `invalid input syntax for type integer: "<value>"`, and `detail` reads `Key (email)=(...)`. The app logs full error objects today (`src/middleware/errorHandler.js`, `src/models/db.js:7`). See `architecture.md` § 2.
2. A single role that both owns the schema and serves requests turns any SQL injection into a possible `DROP TABLE`.
3. Backups hold every user's PII and health data.

## Alternatives considered
- **Plain numbered SQL files with a small in-repo runner (chosen).** It adds no dependency, the owner can read every line, and it matches the course's SQL focus. The cost is that we write and test the runner ourselves.
- **`node-pg-migrate`.** A mature tool with down migrations. It adds a dependency and its supply-chain surface. Rejected by the owner.
- **Keep `schema.sql` plus `db:setup`/`db:reset`.** This cannot change a populated database. Rejected.
- **Recovery: copy only `users` and `roles` before migrating (option B).** The owner chose it first. Review then found three problems: the restore breaks when a migration alters `users`, role IDs clash with the seed, and the copy is a second credential store. Making it correct would cost more than a full backup while protecting less. The owner switched to option C.
- **Recovery: no backup (option A).** Rejected, because accounts could not be recovered.
- **`connect-pg-simple`'s `createTableIfMissing`.** Rejected, because the app would then run DDL at runtime.

## Decision

### 1. Migrations
- Migrations are plain `.sql` files in `database/migrations/`, named `NNNN_short_snake_name.sql`. The number is four digits, sequential, and never reused.
- They are applied by an in-repo runner on the existing `pg` driver, through `npm run db:migrate`.
- A `schema_migrations` table records the version, file name, SHA-256 checksum and `applied_at`.
- **An applied file is never edited.** The runner refuses to run if a checksum has changed.
- Each file runs in its own transaction. The only exception is a file whose first line is `-- migrate:no-transaction`. Such a file holds exactly one statement, such as `CREATE INDEX CONCURRENTLY`, and is Risky tier with Data Engineer sign-off.
- The runner holds a **session-level** `pg_advisory_lock` on one dedicated client for the whole run.
- **Migrations never run on app startup.**

### 2. Forward-only
- There are no down files. A mistake is fixed with a new migration.
- **The default rollback is the app, never the database.** Migrations follow expand-then-contract, so the previous release still runs on the new schema.
- These Data Engineer redlines are binding migration rules:
  - no destructive change without a deprecation plan and a forward fix,
  - no `NOT NULL` on a populated column without a tested backfill,
  - no foreign-key column without an index.
- A destructive file is marked `-- migrate:destructive`. `db:migrate` refuses it unless `--confirm-destructive` is passed.

### 3. Backfills
- A backfill runs inside the migration's transaction, **except** on `glucose_readings` and `events`.
- `glucose_readings` grows by about 105k rows per user per year (`PROJECT_PLAN.md` § 9).
- On those two tables, backfills run as batched updates outside the transaction, with a progress check and Data Engineer review.
- Migrations never depend on rows from `seed.sql`. A backfill that needs a reference row inserts it itself with `ON CONFLICT DO NOTHING`.

### 4. Seed data
- **`database/seed.sql`** holds the default data: roles, the single `site_settings` row, and the starting event types.
  - It runs in **every** environment through `npm run db:seed`, after `db:migrate`.
  - It is safe to rerun:
    - roles and `site_settings` use `ON CONFLICT DO NOTHING`,
    - event types are inserted only when `event_types` is empty, so a renamed or deleted type is not recreated.
  - It never touches `users` or `session`.
  - Code looks reference rows up by name, never by ID.
- **`database/seed-test.sql`** holds test accounts and sample data, run by `npm run db:seed -- --test`. Test accounts with known passwords can therefore never reach production.
  - `db:seed --test` and `db:reset` refuse unless `NODE_ENV` is `development` or `test` **and** `current_database()` is `glucoscope` or `glucoscope_test`.
  - `db:reset` also requires `--yes`.
- Whether the rubric's test accounts may exist in production is left to the auth task. Until then, the answer is no.

### 5. Deploy order
1. `db:migrate`
2. `db:seed`
3. restart the app

The production procedure belongs to T-006.

### 6. Backups and restore (owner's choice: a full backup)
- **Backup:** when migrations are pending and the database is not empty, `db:migrate` first runs `pg_dump --format=custom`. **If the backup fails, no migration runs.**
- **Client tools:** the client must be PostgreSQL 17 or newer. The command is configurable (`PG_CLIENT_CMD`).
  - In dev, it runs inside the compose container.
  - In CI, it comes from the same digest-pinned `postgres:17.x` image, or from a pinned `postgresql-client-17`.
- **Credentials** are passed only through `PG*` environment variables, never on the command line. A failure logs only the exit code.
- **Backup files are classified sensitive:** they hold every user's PII and health data.
  - **Location:** `BACKUP_DIR`, outside the repo and not under `/tmp`. This is checked after `realpath`. The directory has mode 700.
  - **Files:** created exclusively with mode 600. Each name holds a timestamp, a sequence number and the migration version. Files are never overwritten.
  - **Retention:** the newest 5 are kept. Older files are deleted only after the new one passes `pg_restore --list`.
  - **Logging:** contents and paths are never logged beyond the file name.
- **Restore:** `npm run db:restore -- --file <name> --yes`.
  - It refuses while other sessions are connected, so the app must be stopped first.
  - It holds the advisory lock.
  - It shows the backup's age before accepting `--yes`.
  - It drops and recreates `public`, then runs `pg_restore --single-transaction --no-owner`.
  - It accepts files from `BACKUP_DIR` only, and never runs a file as SQL text.
  - Afterwards, it prints the migration version the database is now at, so the matching release is deployed before the app starts.
- **Loss window, accepted by the owner:** data written between the backup and the restore is lost, and the window grows with how long a problem takes to notice.
- **Privacy:** a deleted account's data stays in backups until the newest 5 have rotated past it.

### 7. Test database
- Database tests live in `test-db/` and run with `npm run test:db`:
  - with `--test-concurrency=1`,
  - without the `test/setup.js` tripwire,
  - against `TEST_DATABASE_URL`, as a non-superuser role.
- Before any `DROP`, the suite requires all four of these:
  - the database name parsed from the URL is `glucoscope_test`,
  - `TEST_DATABASE_URL` is not the same as `DATABASE_URL`,
  - `NODE_ENV` is not `production`,
  - `SELECT current_database()` returns `glucoscope_test`.
- Each file starts from a fresh schema.
- `glucoscope_test` is created by a second init script on new volumes. For existing volumes, a documented one-time command does it: `CREATE DATABASE glucoscope_test OWNER …`.
- In CI, a digest-pinned `postgres:17.x` service and the `test:db` step go in the required `scripts` job.

### 8. PostgreSQL version
- The app targets PostgreSQL 17.
- The dev container reports 17.11 (2026-11-19).
- Compose and CI pin the same minor version.

### 9. The `session` table
- It is created by a migration copied from the installed `connect-pg-simple` version's `table.sql`.
- `createTableIfMissing` stays off.
- Its `timestamp(6)` column without a time zone is a library-mandated exception to the TIMESTAMPTZ rule.

### 10. Logging database errors (invariant I9, `contracts.md` § 9)
- For a `pg.DatabaseError`, log only:
  - `code`, `constraint`, `table`, `column` and `routine`,
  - a label naming the query or the request.
- **Never** log any of these:
  - `message`, `detail`, `hint`, `where`, `position`, `stack`,
  - the error object itself.
- This covers the pool listener, `checkConnection`, the error handler, the startup wait (`waitForDatabase` and `server.js`) and the runner.

### 11. Database roles
- `glucoscope_owner` owns the schema. It runs `db:migrate`, `db:seed`, `db:restore` and `db:reset` through `MIGRATION_DATABASE_URL`, which is kept in a separate mode-600 env file that only the `db:*` scripts load.
- `glucoscope_app` serves requests with `SELECT`, `INSERT`, `UPDATE` and `DELETE` only. It is granted these on existing objects and, through `ALTER DEFAULT PRIVILEGES`, on future ones.
- Objects created before the split are handed over with a one-time superuser step, `REASSIGN OWNED BY glucoscope_app TO glucoscope_owner`, run in both `glucoscope` and `glucoscope_test`.

## Consequences
- **Good:**
  - no new dependency;
  - every schema change is reviewed SQL with an enforced checksum;
  - production never runs DDL at runtime;
  - a bad migration can be undone from a full backup;
  - test accounts cannot reach production;
  - logs cannot carry row values;
  - an injection in the app cannot drop tables.
- **Bad / costs:**
  - the runner, backup and restore are ours to build and test;
  - forward-only means mistakes are fixed forward;
  - there is a loss window on restore;
  - backups keep deleted accounts for up to 5 cycles;
  - two database roles and two connection strings to manage.
- **Follow-ups:**
  - **T-009:** runner, seeds, `db:reset`, test database, CI. Blocks schema v1.
  - **T-010:** backup and restore.
  - **T-011:** role split and I9.
  - T-010 and T-011 both block **T-006**, which covers production deploy, the backup location, the restore runbook and the production client.
  - Until T-011 lands, the week-2 xDrip phone test uses synthetic readings (owner's approved default).

## Lenses (major decisions)
- **Value and cost:** no new dependency. Backups use a few MB of disk each, and 5 are kept.
- **User:** nothing visible changes day to day. After a failed migration, users get their history back, except data written after the backup. I9 keeps health data out of logs.
- **Maintainer:** plain SQL with enforced checksums and refusal messages that say what to do next. The cost is owning the runner's tests.
- **Scope and timing:** the build is split three ways. Schema v1 waits only on T-009.
- **Conflict between lenses:** Security and Maintainer favoured splitting roles early, against Scope and timing. Resolved by the owner splitting the build, with T-011 blocking production.
