---
description: Close finished calendar years out of an over-ceiling log-topic file (worklog/support/decisions) into a locked topic-YYYY.md shard, and update the parent's Shards index. (opencode host adapter)
agent: mempenny
---

# MemPenny memory-shard-roll — opencode host adapter

The user invoked this command with: $ARGUMENTS

Execute the MemPenny **memory-shard-roll** flow. The canonical procedure lives in:

    ${MEMPENNY_ROOT}/commands/memory-shard-roll.md

**Read it first with the Read tool** — it is the single source of truth for the closed-year sharding rule, the locked-shard convention, the scripted conservation check, and the locale keys. This file only describes the opencode host differences.

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
Where the source spawns `subagent_type: general-purpose` for the isolated write+verify, use opencode's `subagent_type: "general"` (write-capable), lowercase, with `description` + `prompt`. Preserve the separately-spawned-subagent property and the scripted (not judgment-based) conservation check that every relocated line survived — both are what make shard-roll safe to run without a confirmation prompt.

### D. Command namespace
Sibling commands use the hyphen namespace.

### shard-roll-specific notes
- The first positional arg is the absolute path to a log-topic file (required); `--lang` parses from `$ARGUMENTS`.
- Shard-roll never writes for content in the current (open) year — it only closes a year that has already ended. Reproduce the source's year-boundary logic exactly.
