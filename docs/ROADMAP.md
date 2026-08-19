# Roadmap — what is pending

Living list of known-pending work, in priority order. Each item carries the
evidence that put it here, so a future session (or a different AI) can pick
it up cold. Shipped items move to the [CHANGELOG](../CHANGELOG.md).

## 1. Shard-roll engine ↔ command unification (carried since v1.5.0)

`hooks/shard-roll.sh` (the deterministic year/month/day roller) is still
standalone: `/mempenny-memory-shard-roll` closes finished years with its own
month-heading logic and does not read the day-heading layout the v1.5.0
mover writes. Unify: command invokes the engine; one day/month layout across
mover, command, and `docs/memory-taxonomy-design.md`.

## 2. Nap wave 2 — the other hook-capable hosts

The Gemini/Codex nap port (shipped 2026-08) worked because those hosts adopted
Claude Code's hook shape *and* the hook could travel inside the adapter
MemPenny already ships (extension / plugin). The 2026-08-19 host sweep found
more hosts with session-lifecycle hooks; port when a distribution path exists
per host:

- **Copilot** — hooks (`sessionStart`) via `.github/hooks/*.json`, plus "Agent
  Plugins 1.0" (2026-08-12) packaging agents/commands/rules/hooks. A repo-level
  `.github/hooks/` file applies to the *user's own* repo, not to an installed
  package, so the distribution shape is the plugin primitive — needs a
  `.github`-plugin adapter first. <https://docs.github.com/en/copilot/reference/hooks-reference>
- **Devin CLI** — 8 lifecycle events incl. `SessionStart` at
  `.devin/hooks.v1.json`; also reads Claude Code's `.claude/settings.json` hook
  format directly, and Devin plugins can bundle a `hooks.json` — but plugins
  are in closed beta. <https://docs.devin.ai/cli/extensibility/hooks/overview>
- **Kiro** — `.kiro/hooks/*.json` + global `~/.kiro/hooks/`; triggers include
  Prompt Submit / Agent Spawn, no verified session-start equivalent yet.
  <https://kiro.dev/docs/hooks/>
- **Cursor** (hooks since 1.7, beta), **Cline** (SDK/CLI hooks only, not the
  IDE extensions), **Hermes** (`on_session_start` via plugin code),
  **CodeWhale** (11 TUI lifecycle hooks), **OpenClaw** (cron automations, not
  hooks) — all possible, none has a clean ship-with-the-adapter path today.

## 3. ClawHub packaging check (small)

The OpenClaw skill now also lives at `.agents/skills/mempenny/SKILL.md` (the
Agent Skills standard path, which current OpenClaw discovers and Devin skills
share); `.openclaw/skills/mempenny/SKILL.md` is kept because ClawHub installs
were built against it. Verify what `clawhub install` actually maps, then drop
the redundant copy.
