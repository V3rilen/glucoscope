# Claude Code — Project Entry Point

> **All project conventions, the 6-agent team, the 4 strategic lenses, the review tiers, and the session-start procedure live in [`AGENTS.md`](./AGENTS.md).**
>
> `AGENTS.md` is the canonical source of truth. This file exists so Claude Code finds the same procedure that Codex and other agents read from `AGENTS.md`. Do not duplicate content here — edit `AGENTS.md` only.

## Read this first, every session

1. Open and read **[`AGENTS.md`](./AGENTS.md)** in full.
2. Follow the **Session Start Procedure** at the top of that file: read `/docs` and the task list, or bootstrap the docs if they are not yet bootstrapped (no `contracts.md`).
3. Then respond to the user's request, applying the agent team, review tiers, and hard gates defined there.

## Claude-Code-specific notes

- Reviewers are defined in [`.claude/agents/`](./.claude/agents/). Invoke them via the `Task` / `Agent` tool, one per reviewer, in parallel.
- **You, the main session, act as Review Coordinator.** Follow [`.claude/agents/review-coordinator.md`](./.claude/agents/review-coordinator.md) and dispatch the five reviewers yourself. They are read-only; you do the writing.
- Project permissions and settings live in [`.claude/settings.json`](./.claude/settings.json).

## Anything not covered here

→ See `AGENTS.md`. If `AGENTS.md` doesn't cover it, ask the user — don't guess.
