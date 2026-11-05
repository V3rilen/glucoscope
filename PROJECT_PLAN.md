# Glucoscope — CSE 340 Final Project

Running record of decisions, architecture, and open questions. Updated as we talk.
Rubric: see [PROJECT_RUBRIC.md](PROJECT_RUBRIC.md).

_Last updated: 2026-11-05_

---

## 1. Project Summary (decided)

- **Name:** Glucoscope (repo: https://github.com/V3rilen/glucoscope)
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
| Hosting | App + PostgreSQL on the same self-hosted machine, behind Cloudflare | See section 8 |

### Why PostgreSQL (even with free choice of DB)
- **Time-series fit:** `TIMESTAMPTZ` handles time zones correctly. Window functions and `percentile_cont` let stats (time-in-range, std dev, hourly patterns) run in SQL.
- **Clean xDrip ingestion:** `INSERT ... ON CONFLICT DO NOTHING` drops duplicate uploads.
- **Data integrity:** `CHECK` constraints, enum types, partial unique indexes, and solid FK `CASCADE` / `SET NULL` support (the rubric grades this).
- **Tooling:** pgAdmin exports the ERD the README requires. `connect-pg-simple` stores sessions in the same DB.
- **Growth path:** the TimescaleDB extension could be added later if readings grow large.
- Alternatives considered:
  - **SQLite**: simplest to self-host, but weaker types, time zones, and concurrency.
  - **MySQL/MariaDB**: fine, but weaker time zone and percentile support.

## 3. Roles & Permissions

**Decided:** any user can be a caregiver for any other user, so **caregiving is a relationship, not a role.**
- Account roles are global (one per account). Caregiving is per-person: a row in a `care_links` table between two user accounts.
- Every account is a normal user with their own data and can also be a caregiver for others at the same time.
- Authorization middleware for patient data: allowed if `viewer is the owner` OR `an accepted care_link exists (patient → viewer)`.

**Decided: admins never see glucose records.** Admins cannot view users' readings, manual entries, day comments, or caregiver data. There is no admin bypass in `requirePatientAccess`.
- Admins **may** see metadata: account info, reading *counts*, last upload time, device name, failed upload attempts.
- Admins **may not** see values, trends, stats, entries, or comment text.
- Admins can still delete an account (CASCADE removes the data) without viewing it.
- The clinician role grants **no** automatic data access either. Clinicians only see patients who invited them (section 4).
- This is an application-level rule. Anyone with direct DB access can still read the data, so this belongs in README Known Limitations.

**Account roles** (the rubric needs admin + a secondary role + standard user):

| Role | Rubric slot | Permissions |
|---|---|---|
| `admin` | Admin/Owner | Users and roles, site defaults, help articles, lookup lists, support tickets, operational dashboard. No glucose data |
| `clinician` | Secondary role | Patient panel listing the people who invited them, with summary stats, plus printable reports. Access to any patient's data still requires an accepted care link. No admin powers |
| `user` | Standard user | Owns their own data. Invites caregivers, and acts as a caregiver when invited |

### Clinician role (decided)

- For a doctor or diabetes educator following several patients. The moderator, `support`, and `content editor` ideas were considered and not chosen.
- **The role unlocks tools, not data.** The role adds the panel and reports. Which patients a clinician can see is still decided only by accepted `care_links`, so patients stay in control and `requirePatientAccess` needs no special case.
- Uses the same invite workflow as caregivers, so no extra tables are needed. The panel is a query over `care_links` where the clinician is the caregiver.

Confirmed defaults:
- An admin assigns the role in user management. There is no credential check, and the README should say so under Known Limitations.
- Clinicians have the same abilities as caregivers on a linked patient, including day comments.
- A clinician account is still a normal account and can have its own glucose data.
- With no support role, **admins handle support tickets**.

## 4. Multi-Stage Workflow: Caregiver Access (decided)

- **The patient invites the caregiver.** Caregivers cannot request access.
- Status flow: **pending → accepted / declined**, and **accepted → revoked**.
- Every status change is written to a **history table** (who changed it, from/to status, when, optional note). This meets the rubric's "see status and view history" requirement.
- Both people can see the current status and history of the link.

Confirmed defaults:
- Invite by the email of an existing account. Invites appear in-app on the caregiver's dashboard, so no email sending is needed.
- The invite form shows the same response whether or not the email exists, so it can't be used to discover accounts.
- The patient can cancel a pending invite. Either person can end an accepted link.

## 5. Caregiver Abilities & Comments (decided)

- Read-only view of the patient's dashboard, chart, stats, and readings.
- **Comments are day-specific to start:** each comment belongs to one patient and one calendar date. Reading- or entry-level comments can be added later.
- Comments are user-generated content: authors can edit/delete their own, and the patient can delete any comment on their own days.

Confirmed defaults:
- Patients can also leave notes on their own days, using the same table.
- The "day" is a date in the patient's time zone.
- Comments stay visible to the patient after a link is revoked. The former caregiver loses access to them.

**Moderation:** day comments are private health-related content and staff can't read them, so the patient is the moderator of their own days. The staff flagged-comment queue was removed. The rubric says moderation only applies "if needed", and the README should explain this choice.

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
- **Implement early.** xDrip is already running on the student's phone, and the student knows how to point it at a personal server.
- This is a machine-to-machine JSON endpoint. It's the one non-HTML route and is separate from the SSR pages.
- Expected entry fields (Nightscout format, to be confirmed against real xDrip traffic):
  `type` ("sgv"), `sgv` (mg/dL), `date` (epoch ms), `dateString`, `direction` (trend arrow, e.g. "Flat", "FortyFiveUp"), `device`, `noise`, `filtered`, `unfiltered`, `rssi`.
- Authentication: xDrip sends an `api-secret` header containing the **SHA-1 hash** of the secret in the configured URL (`https://SECRET@domain/api/v1/`).
  - Multi-user means **each user gets their own upload secret**, and the server finds the user by the hashed secret.
- Duplicate protection: unique constraint on `(user_id, reading_time)` for CGM readings + `ON CONFLICT DO NOTHING`.
- xDrip may also call `/api/v1/treatments`, `/api/v1/devicestatus`, and `/api/v1/status.json`. Log real traffic before deciding what else to support.

## 8. Hosting & Deployment (decided: same machine, Cloudflare in front)

The student is handling the server and Cloudflare setup (connection method, domain, OS, uptime). The app still needs the Express-side items below.

Cloudflare handles HTTPS between visitors and Cloudflare, but it doesn't run the app. The machine still runs Node and PostgreSQL.

Still needed on the server:
- **Connection to Cloudflare:** Cloudflare Tunnel (`cloudflared`) recommended (no open ports on the home network, encrypted outbound link). Alternative: proxied DNS + port forwarding, with SSL mode **Full (strict)**, not Flexible.
- **Express behind a proxy:** `app.set('trust proxy', ...)`, otherwise `secure` session cookies won't be set. Use the `CF-Connecting-IP` header for the real client IP in logs and rate limits.
- **Cloudflare security rules:** make sure Bot Fight Mode / WAF rules don't block xDrip's non-browser POSTs to `/api/v1/*`. Add a skip rule if needed.
- **Caching:** never cache logged-in pages. Send `Cache-Control: private, no-store` and don't use "Cache Everything" rules.
- **PostgreSQL:** listen on localhost only, with a dedicated non-superuser app account. Never expose port 5432.
- **Process management:** keep the app and `cloudflared` running across crashes and reboots (a system service or PM2).
- **Backups:** scheduled `pg_dump`, stored off the machine and test-restored at least once.
- **Rate limiting:** on login and on `/api/v1/entries`.
- **Dev/prod separation:** `NODE_ENV=production`, secrets in env vars.

Privacy note: Cloudflare decrypts traffic at its edge, so health data passes through a third party in readable form. Mention this to other users and in the README.

## 9. Architecture Notes (decided)

- MVC:
  - **Models**: data access and domain logic (queries, stats, unit conversion).
  - **Views**: LiquidJS templates (layouts, partials, pages).
  - **Controllers**: handle requests, call models, render views.
  - **Routes**: map URLs to controllers and contain no logic.
- **Middleware**:
  - `requireLogin`
  - `requireRole(...)`
  - `requirePatientAccess`: owner or accepted caregiver only, with no staff bypass
  - validation
  - global error handler
  - 404 handler
- **Error handling** (from rubric): models may try/catch and return consistent empty results; everything else lets errors bubble up to one global error handler. Error pages must not leak stack traces in production.
- **Security** (from rubric): parameterized queries only, validation and sanitization on every form, secure session cookie settings (`httpOnly`, `secure` in prod, `sameSite`), secrets in env vars.
- **Data model:** glucose stored as integer mg/dL, with units converted only for display. Times stored as `TIMESTAMPTZ` and rendered in the user's time zone. Index `(user_id, reading_time)`: CGM produces ~288 readings/day per user (~105k/year).

## 10. Draft Schema (proposed — shows CASCADE vs SET NULL choices)

| Table | Key columns | FK behavior |
|---|---|---|
| `roles` | id, name | |
| `users` | id, email, password_hash, display_name, role_id, timezone, units, target_low, target_high, upload_secret_hash, is_active, created_at | role_id → roles |
| `glucose_readings` | id, user_id, reading_time, mgdl, direction, source (cgm/manual), device, notes | user → **CASCADE** |
| `event_types` | id, name, unit (admin-managed: carbs/g, insulin/u, exercise/min…) | |
| `events` | id, user_id, event_type_id, event_time, amount, notes | user → **CASCADE**; type → RESTRICT |
| `care_links` | id, patient_id, caregiver_id, status, created_at, updated_at; unique(patient, caregiver) | both users → **CASCADE** |
| `care_link_history` | id, care_link_id, from_status, to_status, changed_by, changed_at, note | link → **CASCADE**; changed_by → **SET NULL** |
| `day_comments` | id, patient_id, author_id, comment_date, body, created_at, updated_at | patient → **CASCADE**; author → **SET NULL** |
| `articles` | id, author_id, title, slug, body, category, status (draft/published), timestamps | author → **SET NULL** |
| `site_settings` | key, value (or one typed row): default target range, default units, low/high thresholds, registration open | |
| `support_tickets` | id, user_id, assigned_to, subject, status, timestamps | user → **CASCADE**; assigned_to → **SET NULL** |
| `ticket_messages` | id, ticket_id, author_id, body, created_at | ticket → **CASCADE**; author → **SET NULL** |
| `session` | (managed by connect-pg-simple) | |

## 11. Admin Content & Control

### Decided for now (open to change)
- **Help Center articles**: CRUD, categories, draft/published, slug URLs (`/help/:slug`). The first article should be "Connect xDrip+ to Glucoscope".
- **Site-wide defaults**: default target range, default units, and the low/high thresholds used for color bands.
- **Lookup lists**: the carbs/insulin/exercise event types in manual entry forms, plus optional insulin names. Admin edits show up in the forms right away.
- **Registration**: open to anyone for now. The student will probably close it later, so it should be a `registration_open` site setting rather than a code change.

### Decided for now, open to change: support tickets
- Status flow: **open → assigned → resolved**, with a user-visible status and message thread.
- Covers the rubric's "view and respond to user submissions" requirement. If tickets are dropped, something else must cover it (e.g. a contact form with replies).

### Required by the rubric
- **User management**: list/search/paginate users, change role, disable/enable account, revoke a user's upload secret, delete account.
- **Operational data**:
  - total users, active in last 7 days, new this week
  - **upload health**: readings received in the last hour/24h, users with stale data (no upload for over 1h). Counts and times only, no values
  - failed `api-secret` attempts on `/api/v1/entries`
  - open tickets, pending caregiver invites

### Parked ideas
- Site announcements/banners
- Invite-only registration with admin-generated codes
- Audit log of admin actions
- Separate FAQ (could just be an article category)

## 12. Rubric Deliverables Checklist

- [ ] README: description, ERD image, roles explanation, one test account per role (password `P@$$w0rd!`, not written in README), known limitations
- [ ] GitHub repo with **15+ substantial commits**: repo created and pushed ✔
- [ ] Deployment on own server with production PostgreSQL + env vars, no dev-only code in prod
- [ ] Multi-stage workflow with status + history: caregiver access ✔ (designed)
- [ ] Secondary role with limited permissions: `clinician` ✔ (designed)
- [ ] Admin-managed dynamic content: articles, defaults, lookup lists ✔ (designed)
- [ ] User-submitted content with view/edit/delete + validation: manual entries + day comments ✔ (designed)
- [ ] Admin dashboard: users/roles, content, tickets, operational data
- [ ] Dynamic routes (e.g. `/readings/:id`, `/patients/:id/dashboard`, `/help/:slug`), layouts/partials, query params for filtering/sorting/pagination

## 13. Proposed (not yet decided)

### Feature ideas
- Dashboard: current reading + trend arrow, SVG chart (3h / 24h / 7d / 14d), color bands for low / in range / high, event markers
- Stats: average, min/max, std dev, time-in-range %, GMI (estimated A1C), daily pattern by hour
- User settings: units, target range, time zone, regenerate upload secret
- Readings table with query-param filters/sort/pagination (`?from=&to=&source=&sort=&page=`)
- Printable report page for doctor visits (also a clinician tool)
- Stretch: `/api/v1/treatments` from xDrip, CSV export, email alerts, reading- or entry-level comments

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
    /partials          # header, nav, footer, flash messages
    /pages ...         # one folder per feature
  /public              # css, images (no chart JS)
  /database            # schema.sql, seed.sql
  .env                 # secrets (not committed)
```

### Proposed timeline (~8 weeks)
| Week | Milestone |
|---|---|
| 1 | ESM scaffold, Express + LiquidJS, layouts/partials, DB connection, error handling, live behind Cloudflare with `trust proxy` |
| 2 | Schema v1, accounts, sessions (PG store), bcrypt, roles, auth middleware, **xDrip `/api/v1/entries` + per-user upload secret, tested with a real phone** |
| 3 | Dashboard: current reading, SVG chart |
| 4 | Stats, settings, readings table with filters/pagination |
| 5 | Manual entries (fingerstick/carbs/insulin/exercise) + lookup lists, chart markers |
| 6 | Caregiver invite workflow + history, caregiver views, day comments |
| 7 | Admin dashboard: users/roles, articles, site defaults, tickets, operational data; clinician panel + printable reports |
| 8 | Polish, security pass, README + ERD, final deploy |

## 14. Open Questions

None. The design is settled, and the next step is the week 1 scaffold.
