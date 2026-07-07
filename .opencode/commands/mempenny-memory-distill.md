---
description: Distill a single memory file in-place — replace prose narrative with 1-3 sentences of forward-looking truth. (opencode host adapter)
agent: build
---

# MemPenny memory-distill — opencode host adapter

The user invoked this command with: $ARGUMENTS

Execute the MemPenny **memory-distill** flow. The canonical procedure lives in:

    ${MEMPENNY_ROOT}/commands/memory-distill.md

**Read it first with the Read tool** — it is the single source of truth for the in-place distillation discipline, the locale `distill.*` keys, and the `distill_output_instruction`. This file only describes the opencode host differences.

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

### C. Command namespace
Sibling commands use the hyphen namespace.

### distill-specific notes
- The first positional arg is the absolute path to a single memory file (required); `--lang` parses from `$ARGUMENTS`.
- Distill replaces prose with 1-3 sentences of forward-looking truth — keep the source's `distill_output_instruction` voice exactly (it already constrains length and tone for cross-model reliability). Do not add a second style guide.
