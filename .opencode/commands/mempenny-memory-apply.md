---
description: Apply a previously approved triage table to an auto-memory directory. Creates a full backup first. Rolls back on failure. (opencode host adapter)
agent: build
---

# MemPenny memory-apply — opencode host adapter

The user invoked this command with: $ARGUMENTS

Execute the MemPenny **memory-apply** flow. The canonical procedure lives in:

    ${MEMPENNY_ROOT}/commands/memory-apply.md

**Read it first with the Read tool** — it is the single source of truth for the backup-first discipline, the rollback-on-failure contract, the table-path validation (H3), and the filename-injection guard (H1). This file only describes the opencode host differences.

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
Where the source spawns `subagent_type: general-purpose` for the isolated apply, use opencode's `subagent_type: "general"` (write-capable), lowercase, with `description` + `prompt`. The "separately-spawned subagent with no memory of the proposal step" property is load-bearing (it is what makes apply safe against prompt injection in the source content) — preserve it: spawn a fresh subagent, do not apply inline in the triage context.

### D. Command namespace
Sibling commands use the hyphen namespace.

### apply-specific notes
- The table path is the first positional arg (required); `--dir` / `--lang` parse from `$ARGUMENTS`.
- The H3 path validation (C1 regex + `realpath` + exists + not-a-symlink) and the F-M1 permission sanity checks carry over verbatim — re-implement them in the apply context exactly as written.
