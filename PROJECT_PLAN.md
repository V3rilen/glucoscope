# Glucoscope — CSE 340 Final Project

Running record of decisions, architecture, and open questions. Updated as we talk.
Rubric: see [PROJECT_RUBRIC.md](PROJECT_RUBRIC.md).

_Last updated: 2026-11-04_

---

## 1. Project Summary (decided)

- **Name:** Glucoscope (git repo initialized 2026-11-04)
- A website + backend for people with diabetes to view their blood glucose data and share it with caregivers.
- Built for personal use first, but must support multiple independent users.
- CGM data comes from **xDrip+** (open source), which uploads to the site using the Nightscout-style API.
- **Self-hosted** by the student. The instructor allows any host and any relational DB, so the rubric's Render/PostgreSQL items don't apply as written.
- Scope target: enough work to build and keep expanding for **half a semester** (~7–8 weeks).

## 2. Tech Stack (decided)

| Layer | Choice | Notes |
|---|---|---|
| Runtime / framework | Node.js + Express | |
| Module system | **ESM only** (`import`/`export`, `"type": "module"`) | Rubric: `require` not allowed |
| Views | LiquidJS | All pages server-side rendered |
| Charts | Server-rendered (no client-side chart libraries) | Plan: inline SVG generated on the server |
| Database | **PostgreSQL**, self-hosted | Still recommended after host/DB requirement was relaxed (see below) |
| Auth | `express-session` + bcrypt | Rubric: sessions, no JWT |
| Session store | PostgreSQL-backed (e.g. `connect-pg-simple`) — proposed | Default MemoryStore is dev-only and loses sessions on restart |
| Hosting | Self-hosted by student | |

### Why PostgreSQL (even with free choice of DB)
- **Time-series fit:** `TIMESTAMPTZ` handles time zones correctly. Window functions and `percentile_cont` let stats (time-in-range, std dev, hourly patterns) run in SQL.
- **Clean xDrip ingestion:** `INSERT ... ON CONFLICT DO NOTHING` drops duplicate uploads.
- **Data integrity:** `CHECK` constraints, enum types, partial unique indexes, and solid FK `CASCADE` / `SET NULL` support (the rubric grades this).
- **Tooling:** pgAdmin exports the ERD the README requires. `connect-pg-simple` stores sessions in the same DB.
- **Growth path:** the TimescaleDB extension could be added later if readings grow large.
- Alternatives considered:
  - **SQLite**: simplest to self-host, but weaker types, time zones, and concurrency.
  - **MySQL/MariaDB**: fine, but weaker time zone and percentile support.

## 3. Roles & Permissions (decided in principle — see open question on the secondary role's name)

**Decision:** any user can be a caregiver for any other user, so **caregiving is a relationship, not a role.**
- Account roles are global (one per account). Caregiving is per-person: "Alice can see Bob's data" is a row in a `care_links` table between two user accounts.
- Every account is a normal user with their own data and can also be a caregiver for others at the same time.
- This avoids multi-role complexity. The real question isn't "is this person a caregiver?" but "is this person an *accepted* caregiver *of this specific user*?", and only a relationship table can answer that.
- Authorization middleware for patient data: allowed if `viewer is the owner` OR `an accepted care_link exists (patient → viewer)`. Admins get no automatic access to glucose data (pending decision).

**Account roles** (the rubric needs admin + a secondary role + standard user):

| Role | Rubric slot | Permissions |
|---|---|---|
| `admin` | Admin/Owner | Everything: users and roles, site settings, all content, moderation, operational dashboard |
| `moderator` (name TBD) | Secondary role | Limited staff role: manage help articles/announcements, moderate flagged comments, respond to support tickets. **Cannot** change roles, site settings, or view glucose data |
| `user` | Standard user | Owns their own data. Can invite and accept caregivers, comment as a caregiver |

## 4. Multi-Stage Workflow: Caregiver Access (decided)

- Status flow: **pending → accepted / declined**, and **accepted → revoked**.
- Every status change is written to a **history table** (who changed it, from/to status, when, optional note). This meets the rubric's "see status and view history" requirement.
- Both people can see the current status and history of the link.
- Who initiates is still open (see questions).

## 5. Caregiver Abilities (decided)

- Read-only view of the patient's dashboard, chart, stats, and readings.
- **Can leave comments and notes** on the patient's data, e.g. on a specific reading, event, or day.
- Comments are user-generated content: authors can edit/delete their own, the patient can delete comments on their data, and staff can moderate flagged comments.

## 6. Manual Entry (decided)

- Users can log entries by hand:
  - **fingerstick readings**
  - **carbs**
  - **insulin**
  - **exercise**
- This is the main "user-submitted content with view/edit/delete + validation" requirement.
- Manual readings are stored with `source = 'manual'` so they're distinct from CGM data and can be edited. CGM data is read-only.

## 7. Required Integration: xDrip+ Uploads (decided)

- Must support **`POST /api/v1/entries`**. xDrip+ uploads CGM readings here as a JSON array.
- This is a machine-to-machine JSON endpoint. It's the one non-HTML route and is separate from the SSR pages.
- Expected entry fields (Nightscout format, to be confirmed against real xDrip traffic):
  `type` ("sgv"), `sgv` (mg/dL), `date` (epoch ms), `dateString`, `direction` (trend arrow, e.g. "Flat", "FortyFiveUp"), `device`, `noise`, `filtered`, `unfiltered`, `rssi`.
- Authentication: xDrip sends an `api-secret` header containing the **SHA-1 hash** of the secret in the configured URL (`https://SECRET@domain/api/v1/`).
  - Multi-user means **each user gets their own upload secret**, and the server finds the user by the hashed secret.
- Duplicate protection: unique constraint on `(user_id, reading_time)` for CGM readings + `ON CONFLICT DO NOTHING`.
- xDrip may also call `/api/v1/treatments`, `/api/v1/devicestatus`, and `/api/v1/status.json`. Log real traffic before deciding what else to support.

## 8. Architecture Notes (decided)

- MVC:
  - **Models**: data access and domain logic (queries, stats, unit conversion).
  - **Views**: LiquidJS templates (layouts, partials, pages).
  - **Controllers**: handle requests, call models, render views.
  - **Routes**: map URLs to controllers and contain no logic.
- **Middleware**:
  - `requireLogin`
  - `requireRole('admin' | 'moderator')`
  - `requirePatientAccess`: owner or accepted caregiver
  - validation
  - global error handler
  - 404 handler
- **Error handling** (from rubric): models may try/catch and return consistent empty results; everything else lets errors bubble up to one global error handler. Error pages must not leak stack traces in production.
- **Security** (from rubric): parameterized queries only, validation and sanitization on every form, secure session cookie settings (`httpOnly`, `secure` in prod, `sameSite`), secrets in env vars.
- **Data model:** glucose stored as integer mg/dL, with units converted only for display. Times stored as `TIMESTAMPTZ` and rendered in the user's time zone. Index `(user_id, reading_time)`: CGM produces ~288 readings/day per user (~105k/year).

## 9. Draft Schema (proposed — shows CASCADE vs SET NULL choices)

| Table | Key columns | FK behavior |
|---|---|---|
| `roles` | id, name | |
| `users` | id, email, password_hash, display_name, role_id, timezone, units, target_low, target_high, upload_secret_hash, is_active, created_at | role_id → roles |
| `glucose_readings` | id, user_id, reading_time, mgdl, direction, source (cgm/manual), device, notes | user → **CASCADE** |
| `event_types` | id, name, unit (admin-managed: carbs/g, insulin/u, exercise/min…) | |
| `events` | id, user_id, event_type_id, event_time, amount, notes | user → **CASCADE**; type → RESTRICT |
| `care_links` | id, patient_id, caregiver_id, status, created_at, updated_at; unique(patient, caregiver) | both users → **CASCADE** |
| `care_link_history` | id, care_link_id, from_status, to_status, changed_by, changed_at, note | link → **CASCADE**; changed_by → **SET NULL** |
| `comments` | id, patient_id, author_id, reading_id?, event_id?, comment_date?, body, is_flagged, created_at, updated_at | patient → **CASCADE**; author → **SET NULL**; reading/event → CASCADE |
| `articles` | id, author_id, title, slug, body, category, status (draft/published), timestamps | author → **SET NULL** |
| `announcements` | id, author_id, message, level, starts_at, ends_at | author → **SET NULL** |
| `session` | (managed by connect-pg-simple) | |

## 10. Admin Content & Control (brainstorm — not yet decided)

### Content the admin manages (rubric #5: "core site content")
- **Help Center articles**: CRUD, categories, draft/published, slug URLs (`/help/:slug`). Examples:
  - **"Connect xDrip+ to Glucoscope"** setup guide (genuinely needed)
  - Treating a low
  - Reading your time-in-range
  - Sharing with a caregiver
- **Site announcements/banners**: shown in the layout partial, with start/end dates and severity (info/warning). Example: "Server maintenance Saturday 10pm".
- **Event types / lookup lists**: the carbs/insulin/exercise categories in manual entry forms, plus optional insulin names (e.g. rapid-acting vs long-acting). Admin edits show up in the forms right away.
- **Site-wide defaults**: default target range (70–180), default units, low/high thresholds used for color bands.
- **FAQ** (could just be an article category).

### Control the admin has
- **User management**:
  - list/search/paginate users
  - change role
  - disable/enable account
  - revoke a user's upload secret (stops a compromised phone from uploading)
  - delete account (CASCADE removes their data)
- **Registration control** (good fit for a self-hosted site):
  - open / closed / **invite-only**
  - admin generates invite codes with expiry and usage tracking (an `invites` table)
- **Moderation**: queue of flagged comments with delete or clear-flag.
- **Audit log**: records admin actions (role changed, user disabled, article deleted) with who/when. Also good evidence for the rubric's "thoughtful design".

### Operational data on the admin dashboard
- Total users, active in last 7 days, new this week
- **Upload health**: readings received in the last hour/24h, and users with stale data (no upload for over 1h), since xDrip connection problems are the most common issue
- Failed `api-secret` attempts on `/api/v1/entries` (security signal)
- Pending caregiver requests, flagged comments, open support items
- DB size / reading counts (nice-to-have)

## 11. Rubric Deliverables Checklist

- [ ] README: description, ERD image, roles explanation, one test account per role (password `P@$$w0rd!`, not written in README), known limitations
- [ ] GitHub repo with **15+ substantial commits**: git initialized ✔
- [ ] Deployment on own server with production PostgreSQL + env vars, no dev-only code in prod
- [ ] Multi-stage workflow with status + history: caregiver access ✔ (designed)
- [ ] Admin-managed dynamic content (brainstorming)
- [ ] User-submitted content with view/edit/delete + validation: manual entries + comments ✔ (designed)
- [ ] Admin dashboard: users/roles, content, submissions, moderation, operational data
- [ ] Dynamic routes (e.g. `/readings/:id`, `/patients/:id/dashboard`, `/help/:slug`), layouts/partials, query params for filtering/sorting/pagination

## 12. Proposed (not yet decided)

### Feature ideas
- Dashboard: current reading + trend arrow, SVG chart (3h / 24h / 7d / 14d), color bands for low / in range / high, event markers
- Stats: average, min/max, std dev, time-in-range %, GMI (estimated A1C), daily pattern by hour
- User settings: units, target range, time zone, regenerate upload secret
- Readings table with query-param filters/sort/pagination (`?from=&to=&source=&sort=&page=`)
- Printable report page for doctor visits
- Optional second workflow: support tickets (open → assigned → resolved) for the moderator role to handle
- Stretch: `/api/v1/treatments` from xDrip, CSV export, email alerts

### Proposed folder structure
```
glucoscope/
  server.js            # app setup, middleware, mount routes
  /src
    /routes            # URL -> controller mapping (incl. /api/v1 for xDrip)
    /controllers       # request handling
    /models            # DB queries + domain logic
    /middleware        # auth, roles, patient access, validation, error handling
    /utils             # SVG chart builder, unit conversion, stats helpers
  /views
    /layouts           # base layout
    /partials          # header, nav, footer, flash messages, announcement banner
    /pages ...         # one folder per feature
  /public              # css, images (no chart JS)
  /database            # schema.sql, seed.sql
  .env                 # secrets (not committed)
```

### Proposed timeline (~8 weeks)
| Week | Milestone |
|---|---|
| 1 | ESM scaffold, Express + LiquidJS, layouts/partials, DB connection, error handling, deploy to own server early |
| 2 | Schema v1, accounts, sessions (PG store), bcrypt, roles, auth middleware |
| 3 | xDrip `/api/v1/entries` endpoint + per-user upload secret; test with a real phone |
| 4 | Dashboard: current reading, SVG chart, stats |
| 5 | Settings, readings table with filters/pagination, manual entries (fingerstick/carbs/insulin/exercise) |
| 6 | Caregiver access workflow + history, caregiver views, comments |
| 7 | Admin + moderator dashboards: users/roles, content, moderation, operational data |
| 8 | Polish, security pass, README + ERD, final deploy |

## 13. Open Questions

- Admin content: which items from section 10 to keep?
- Secondary role name: `moderator`, `staff`, `support`?
- Should there also be support tickets for the secondary role to handle (also covers "admin responds to user submissions")?
- Caregiver workflow: who starts it — the patient invites a caregiver, the caregiver requests access, or either?
- Can admins see users' glucose data, or only account metadata (privacy)?
- Comments: attach to a reading, an event, a whole day, or all three?
- Is xDrip already set up so we can capture real requests early?
- Hosting setup: same machine for app + DB? Reverse proxy / HTTPS plan (xDrip and secure cookies both need HTTPS)?
