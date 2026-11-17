<!--
Read AGENTS.md before opening this pull request.
Trivial tier (typo / lockfile bump / etc., per AGENTS.md § 5): keep "Task" + "Summary" and delete the rest.
-->

## Task

- **Task ID:** [T-NNN](../../tree/main/tasks/T-NNN.md)
- **Type:** feat | fix | chore | refactor | docs
- **Tier:** Trivial | Standard | Risky (see `AGENTS.md` § 5)

## Summary

<!-- 2–4 sentences. What changes. Why now. Name any file changed under .githooks/, scripts/ or .github/. -->

## Plan approval

- **Plan approved by:** <copy the task's activity-log approval line> (`AGENTS.md` § 7 step 4b)

## Regression safety / contracts (see `AGENTS.md` § 7)

> Proves this change didn't silently break a documented contract. "None" is a valid answer and must be stated, not omitted.

- **Contracts touched** (routes / schema fields / events / public signatures / integrations / env vars / flags from `/docs/contracts.md`): none / list them
- [ ] If any contract was touched, it is reflected in `/docs/contracts.md` (and `data-model.md`) **in this pull request**, with the `unanimous-consensus` trailer on that commit
- **Compatibility:** backward-compatible / migration at `<path>`
- [ ] The tests that exercise the touched contracts were run and pass — a green unit suite alone does not satisfy this

## Review verdict

> Full record: the `## Review` section of the task file.

- **Verdict:** PASS | PASS WITH ITEMS
- [ ] Product &nbsp; - [ ] Architect &nbsp; - [ ] Engineer &nbsp; - [ ] Data Engineer &nbsp; - [ ] Verifier &nbsp; - [ ] Review Coordinator &nbsp; (tick those required for the tier)
- [ ] No redlines crossed, or accepted by the owner on the record: <task activity-log line>
- **Rollback:** <one line>

## Out of scope (for this pull request)

- …
