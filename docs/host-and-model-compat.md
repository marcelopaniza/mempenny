# Host & model compatibility

MemPenny runs on more than one AI host and more than one model. This page is the
honest matrix: what works where, what doesn't, and why.

## The two compatibility axes

These are independent:

- **Host** — the agent harness (Claude Code, opencode, Codex, …). Determines
  *packaging*: how MemPenny is installed, whether its lifecycle hook (the nap
  scheduler) can run, and how commands are namespaced.
- **Model** — the LLM (Claude Sonnet/Opus, GLM, GPT-5, Gemini). Determines
  *reliability*: how closely the model follows the prompt's output contracts.

## Host matrix

| Host | Tier | Clean / Restore | Scheduled nap | Adapter shipped |
|---|---|:---:|:---:|---|
| **Claude Code** | Full | ✅ | ✅ auto | `.claude-plugin/` (reference). Commands: `/mempenny:clean` (colon). |
| **opencode** | Full | ✅ | ✅ notify · opt-in auto | `.opencode/` (env shim + nap plugin + thin adapters). Commands: `/mempenny-clean` (hyphen). Shares the memory dir + config with Claude Code. |
| **Codex** | Rules + nap | via `AGENTS.md` / skill | 🔔 reminder | `.codex-plugin/plugin.json` manifest + plugin-shipped nap hook (`hooks/hooks.json`; trust it once via `/hooks`). Installable via `codex plugin marketplace add`. |
| **Gemini / Antigravity** | Rules + nap | via `AGENTS.md` | 🔔 reminder | `gemini-extension.json` (`contextFileName: AGENTS.md`) + extension-shipped nap hook (`hooks/hooks.json`). `gemini extensions install <repo>`. |
| **Devin** | Rules-only | via `AGENTS.md` | — | `.devin-plugin/plugin.json` manifest (Devin plugins are in closed beta; Devin also reads `AGENTS.md` natively). Skill also discoverable at `.agents/skills/mempenny/`. |
| **Hermes** | Rules-only | via `AGENTS.md` | — | `plugin.yaml` (the installer places it under `~/.hermes/plugins/mempenny/`). Hermes also reads `AGENTS.md` natively. |
| **Cursor** | Rules-only | copy rules file | — | `.cursor/rules/mempenny.mdc`. Current Cursor also reads `AGENTS.md` natively. |
| **Windsurf (Devin Desktop) / Cline** | Rules-only | copy rules file | — | `.devin/rules/mempenny.md` (preferred; `.windsurf/rules/mempenny.md` is the legacy fallback), `.clinerules/mempenny.md`. Both also read `AGENTS.md` natively. |
| **Kiro / Copilot** | Rules-only | copy rules file | — | `.kiro/steering/mempenny.md`, `.github/copilot-instructions.md`. Both also read `AGENTS.md` natively. |
| **CodeWhale / Swival** | Rules-only | via `AGENTS.md` | — | Zero setup — read `AGENTS.md` from the project root. |
| **OpenClaw** | Rules-only | skill | — | `.agents/skills/mempenny/SKILL.md` (Agent Skills standard path). `.openclaw/skills/mempenny/SKILL.md` kept for ClawHub installs. |

**Why "rules-only" for most hosts.** MemPenny's core mechanics are a lifecycle
hook (the nap scheduler), a bash script, subagent spawning, and filesystem-
mutating apply logic. A rules-only host loads the ruleset (via `AGENTS.md` or
its native rules file) and follows the cleanup procedure manually — the strategy,
guards, and discipline hold, but the commands are not installed as first-class
slash commands. The scheduled nap is no longer Claude-Code-and-opencode-only:
Gemini and Codex adopted Claude Code's hook shape, so those two also get a
session-start nap reminder (next section). The rules files are a compact
distillation of `AGENTS.md` (the canonical, fuller version); keep them aligned
when editing.

## The scheduled nap beyond Claude Code

One schedule, four behaviors — all driven by the same `schedules` entry in
`~/.claude/mempenny.config.json` (written by `/mempenny-nap` on Claude Code or
opencode, or by hand):

```json
{
  "schedules": {
    "/abs/path/to/memory": { "frequency": "daily", "time": "03:00" }
  }
}
```

- **Claude Code** — the plugin-shipped `SessionStart` hook injects a nudge and
  the model runs `/mempenny:clean --yes`. Fully automatic.
- **opencode** — the `mempenny-nap.ts` plugin fires a desktop notification
  pointing at `/mempenny-clean --yes`. Add `"mode": "auto"` to the schedule
  entry and it starts `/mempenny-clean --yes` in the new session instead
  (notify stays the default; a failed auto-invoke falls back to the
  notification).
- **Gemini** — the extension ships the same hook (`hooks/hooks.json` +
  `hooks/nap-check.sh`); Gemini's hooks arrived in v0.26.0 (Jan 2026) and
  deliberately mirror Claude Code's contract, down to the
  `hookSpecificOutput.additionalContext` output field and a
  `CLAUDE_PROJECT_DIR` compatibility alias. When a nap is due, the session
  starts with a note that it's due, and the model offers the rules-only
  cleanup per the `AGENTS.md` already in its context. Consent-first — nothing
  runs without the user.
- **Codex** — Codex plugins ship hooks the same way (hooks stable since
  v0.124.0, Apr 2026; enabled by default — no feature flag). Same reminder
  behavior, pointing at the plugin's memory-hygiene skill. One extra step:
  Codex never trusts plugin hooks silently, so run `/hooks` once after
  installing and trust the MemPenny nap hook.

Mechanics shared by all of it: the three host entries live in one
`hooks/hooks.json` (each entry guards on env vars only its own host sets, so
every host runs exactly one real check); `hooks/nap-check.sh` needs `jq` on
PATH and skips silently without it; each host keeps its own last-fired state
(Claude under `~/.claude/data/mempenny/`, Gemini/Codex host-prefixed under
`~/.local/share/mempenny/`), so each host reminds independently at most once
per due period. Deterministic coverage: `tests/run-napcheck.sh`.

## Model matrix

MemPenny is tuned on Claude Sonnet/Opus and runs on other competent coding models.

| Model | Triage | Distillation | Notes |
|---|:---:|:---:|---|
| Claude Sonnet 4.5+ | ✅ | ✅ | Reference. |
| Claude Opus | ✅ | ✅ | |
| GLM 4.6+ (Coder) | ✅ | ✅ | Strict output schemas are on by default. |
| GPT-5 / GPT-5-Codex | ✅ | ✅ | |
| Gemini 2.5 Pro | ✅ | ⚠️ | Distillation can be verbose; review recommended. |

**Conservation is non-negotiable on every model.** A scripted check (not a
judgment call) verifies that every line of every old file is accounted for in
what survives, before anything old is deleted. A model that drops content fails
loudly with `MIGRATION FAILED: conservation check found <N> unaccounted lines`
and writes nothing.

Classification *quality* (which action a file gets: DELETE vs ARCHIVE vs DISTILL)
varies by model. The v1.2 bar is conservation only; a per-model F1 ≥ 0.85 quality
bar is deferred to v1.3, once there is real failure data to score against. Until
then, the dry-run `/mempenny-memory-triage` lets you review every proposed action
before anything is applied.

## Verifying a model yourself

```bash
# From a clone of mempenny:
for f in tests/fixtures/v09/*/; do
  work="$(mktemp -d)"
  cp -a "$f/." "$work/"
  # in your host, run on the COPY:
  #   /mempenny-clean --dir "$work" --yes
done
```

A passing model reports `MIGRATION APPLIED` with no unaccounted lines on every
fixture. See [`tests/run-smoke.sh`](../tests/run-smoke.sh) for the structural
fixture check that runs without an LLM.

## Design rationale

- **One source tree, thin adapters.** The 4,000-line procedure lives once in
  `commands/*.md`. The opencode adapters in `.opencode/commands/` are thin — they
  point at the source and add only the host-specific differences (env vars,
  config path, subagent syntax). Nothing is forked.
- **Claude Code is unchanged.** Existing users see zero behavior change. The
  opencode layer is purely additive.
- **Shared memory, shared config.** opencode resolves the same memory directory
  Claude Code populated (via the project-id slug rule) and reads the same
  `~/.claude/mempenny.config.json` when that dir exists — so a user running both
  hosts gets zero-setup continuity.
- **Namespaced env vars.** The opencode env shim sets `MEMPENNY_*` vars only; it
  never sets `CLAUDE_*`, so it cannot collide with a real Claude Code install on
  the same machine.

See the v1.2 PR plan at [`docs/pr-opencode-and-multi-model.md`](pr-opencode-and-multi-model.md)
for the gap-by-gap analysis this port was built from.
