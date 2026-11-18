# Architectural Decision Records

One file per significant decision: one that shapes the stack, the architecture, a trust boundary, or something a future reader would otherwise ask "why?" about.

## Conventions

- **File name:** `NNNN-short-kebab-title.md`. The number is four digits and sequential (`0001`, `0002`, …). Numbers are never reused.
- **Template:** copy [`_TEMPLATE.md`](./_TEMPLATE.md).
- **Status lifecycle:** `proposed → accepted → deprecated | superseded`.
  - `proposed`: written up, not yet agreed by the owner.
  - `accepted`: in force.
  - `deprecated`: no longer applies, and nothing replaces it.
  - `superseded`: replaced. The status line names the new record (`superseded by 0007`).
- **Past records are never edited.** To change a decision, write a new record that supersedes the old one. The only edit allowed to an old record is its status line, to mark it `deprecated` or `superseded by NNNN`.
- Records live in `/docs`, so adding one needs unanimous 6-agent consensus (`AGENTS.md` § 0 Step 4).
- When the owner settles a deadlock or explicitly accepts crossing a redline as a lasting decision, that decision is recorded here (`AGENTS.md` § 0 Step 4, § 8).

## Index

| # | Title | Status |
|---|---|---|
| [0001](./0001-foundational-stack.md) | Foundational stack | accepted |

---

**Update this doc when** a record is added, or a record's status changes (add or update its index row), or the conventions above change.
