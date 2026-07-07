---
description: Per-entry reduction pass for an over-ceiling reference-topic file (charter/pending/worklog/support/traps/rules/decisions/reference). Distinct from memory-distill, which operates on a whole file. (opencode host adapter)
agent: mempenny
---

# MemPenny memory-curate — opencode host adapter

The user invoked this command with: $ARGUMENTS

Execute the MemPenny **memory-curate** flow. The canonical procedure lives in:

    ${MEMPENNY_ROOT}/commands/memory-curate.md

**Read it first with the Read tool** — it is the single source of truth for the per-`###`-entry keep/archive/delete discipline, the topic-type guard, and the locale keys. This file only describes the opencode host differences.

Apply these **opencode host adaptations** (override the source wherever they conflict):

### A. Paths & environment
The env shim sets `MEMPENNY_HOST=opencode`, `MEMPENNY_ROOT`, `MEMPENNY_DATA_DIR`. Substitute:

- `${CLAUDE_PLUGIN_ROOT}` → `${MEMPENNY_ROOT}`
- `${CLAUDE_PLUGIN_DATA}` → `${MEMPENNY_DATA_DIR}`
- `${CLAUDE_PROJECT_DIR}` → the current working directory

### B. Config path (shared with Claude Code)
1. `${MEMPENNY_CONFIG_PATH}` if set.
2. Else `~/.claude/mempenny.config.json` if `~/.claude/` exists.
3. Else `~/.config/opencode/mempenny.config.json`.

### C. Subagents (opencode Task tool)
Where the source spawns `subagent_type: general-purpose` for the isolated apply, use opencode's `subagent_type: "general"` (write-capable), lowercase, with `description` + `prompt`. Preserve the separately-spawned-subagent property — curate's writes must run in a fresh context, not the one that read the untrusted source content.

### D. Command namespace
Sibling commands use the hyphen namespace.

### curate-specific notes
- The first positional arg is the absolute path to a topic file (required); `--lang` and `--yes` parse from `$ARGUMENTS`.
- Curate operates entry-by-entry (`###` sections); do not collapse the whole file (that is distill's job). Backup-first behavior is unchanged; `/mempenny-restore` reverses any pass.
