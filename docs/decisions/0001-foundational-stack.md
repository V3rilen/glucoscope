# 0001 — Foundational stack

- **Status:** accepted
- **Date:** 2026-11-17. This records decisions the owner made in `PROJECT_PLAN.md`, committed 2026-11-04 to 2026-11-05 (`git log -- PROJECT_PLAN.md`).
- **Deciders:** the owner (Verilen). Recorded during the T-001 docs bootstrap.
- **Task:** T-001.4

## Context
Glucoscope is a CSE 340 final project: a server-rendered app for viewing CGM glucose data uploaded by xDrip+ and sharing it with caregivers, with several users and roles (`PROJECT_PLAN.md` § 1). The course rubric fixes part of the stack: Node.js with Express, EJS or Liquid views, ESM only, `express-session` authentication (not JWT), and password hashing (`PROJECT_RUBRIC.md`). The instructor lets students choose any host and any relational database (`PROJECT_PLAN.md` § 1).

## Alternatives considered
- **Views: EJS vs LiquidJS.** The course allows both. The owner chose LiquidJS.
- **Database: SQLite.** Simplest to self-host, but has weaker types, time-zone handling and concurrency (`PROJECT_PLAN.md` § 2).
- **Database: MySQL / MariaDB.** Workable, but has weaker time-zone and percentile support (§ 2).
- **Database: PostgreSQL.** Chosen (see Decision).
- **Session store: the default MemoryStore.** Rejected because it is meant for development only and loses sessions on restart (§ 2).
- **Hosting: Render (the rubric's default).** The owner self-hosts instead, with the instructor's permission (§ 1, § 8).

## Decision

| Layer | Choice | Status on 2026-11-17 |
|---|---|---|
| Language | JavaScript, ESM only (`"type": "module"`) | implemented (`package.json`) |
| Runtime / framework | Node.js ≥ 22.9.0, Express 5 | implemented (`package.json`, `src/app.js`) |
| Views | LiquidJS, all pages server-rendered, no client-side framework; charts as server-generated SVG | LiquidJS implemented (`src/app.js:11-24`); charts planned |
| Database | PostgreSQL via `pg` | driver implemented (`src/models/db.js`); no schema yet |
| Auth | `express-session` + bcrypt; sessions stored in PostgreSQL via `connect-pg-simple` | **decided, not yet implemented**: none of these is in `package.json` |
| Architecture | MVC: routes, controllers, models, views, middleware | implemented as a scaffold (`src/`) |
| Hosting | App and PostgreSQL on one self-hosted machine, with Cloudflare in front | decided; deployment details `UNKNOWN` (T-006) |
| Secrets | Environment variables, loaded from a gitignored `.env` | implemented (`.gitignore`, `.env.example`, npm scripts) |
| Package manager / tests | npm; built-in `node:test` | npm implemented; `node:test` chosen, set up in T-004 |

PostgreSQL was chosen for (§ 2):
- **Time handling:** `TIMESTAMPTZ`, plus window and percentile functions for glucose statistics.
- **Ingestion:** `INSERT … ON CONFLICT DO NOTHING` drops duplicate xDrip+ uploads.
- **Integrity:** `CHECK`, enum and foreign-key `CASCADE` / `SET NULL` constraints, which the rubric grades.
- **Tooling:** pgAdmin can export the ERD.
- **Growth:** TimescaleDB is a possible later step.

## Consequences
- **Good:**
  - It meets the rubric.
  - It runs as one process plus one database on one machine.
  - All dependencies are permissively licensed (`architecture.md` § 5.2).
  - SQL can do the statistics.
- **Bad / costs:**
  - Self-hosting puts uptime, backups, patching and the Cloudflare-to-origin security on the owner (T-006).
  - Cloudflare decrypts health data at its edge (`PROJECT_PLAN.md` § 8).
  - Server-rendered SVG charts mean no interactive charts.
  - PostgreSQL-specific SQL makes changing databases expensive.
- **Follow-ups:** T-004 (tests), T-005 (migration tooling), T-006 (deployment and rollback).

## Lenses
Not re-run here: this record documents decisions the owner already made in `PROJECT_PLAN.md`. A record that supersedes this one runs the lenses.
