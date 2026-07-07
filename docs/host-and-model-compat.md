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
| **Claude Code** | Full | ✅ | ✅ | `.claude-plugin/` (reference). Commands: `/mempenny:clean` (colon). |
| **opencode** | Full | ✅ | ✅ | `.opencode/` (env shim + notify-only nap + thin adapters). Commands: `/mempenny-clean` (hyphen). Shares the memory dir + config with Claude Code. |
| **Codex** | Rules-only | via `AGENTS.md` | — | `.codex-plugin/plugin.json` manifest. Installable via `codex plugin`. |
| **Gemini / Antigravity** | Rules-only | via `AGENTS.md` | — | `gemini-extension.json` (`contextFileName: AGENTS.md`). `gemini extensions install <repo>`. |
| **Devin** | Rules-only | via `AGENTS.md` | — | `.devin-plugin/plugin.json` manifest. |
| **Hermes** | Rules-only | via `AGENTS.md` | — | `plugin.yaml`. |
| **Cursor** | Rules-only | copy rules file | — | `.cursor/rules/mempenny.mdc`. |
| **Windsurf / Cline** | Rules-only | copy rules file | — | `.windsurf/rules/mempenny.md`, `.clinerules/mempenny.md`. |
| **Kiro / Copilot** | Rules-only | copy rules file | — | `.kiro/steering/mempenny.md`, `.github/copilot-instructions.md`. |
| **CodeWhale / Swival** | Rules-only | via `AGENTS.md` | — | Zero setup — read `AGENTS.md` from the project root. |
| **OpenClaw** | Rules-only | skill | — | `.openclaw/skills/mempenny/SKILL.md`. |

**Why "rules-only" for most hosts.** MemPenny's core mechanics are a lifecycle
hook (the nap scheduler), a bash script, subagent spawning, and filesystem-
mutating apply logic. A rules-only host loads the ruleset (via `AGENTS.md` or
its native rules file) and follows the cleanup procedure manually — the strategy,
guards, and discipline hold, but there is no auto-schedule and the commands are
not installed as first-class slash commands. The rules files are a compact
distillation of `AGENTS.md` (the canonical, fuller version); keep them aligned
when editing.

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
