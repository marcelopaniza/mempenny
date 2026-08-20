---
description: Content-preserving fallback split for an over-ceiling topic file with no other reduction path — the main file becomes an INDEX and its items become PAGES the index points at. (opencode host adapter)
agent: mempenny
---

# MemPenny memory-auto-split — opencode host adapter

The user invoked this command with: $ARGUMENTS

Execute the MemPenny **memory-auto-split** flow. The canonical procedure lives in:

    ${MEMPENNY_ROOT}/commands/memory-auto-split.md

**Read it first with the Read tool** — it is the single source of truth for the eligibility check (the 5 auto-split-eligible basenames), the backup, the deterministic `hooks/auto-split.sh` invocation, and the index-update step. This file only describes the opencode host differences.

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

### auto-split-specific notes
- The first positional arg is the absolute path to a topic file (required); `--lang` parses from `$ARGUMENTS`. There is no `--yes` flag and no confirmation gate — same as the source (see its "Why no confirmation gate").
- Step 5 runs `bash "${MEMPENNY_ROOT}/hooks/auto-split.sh" …` directly via Bash in this context — do NOT spawn a subagent for it; the source explains why (deterministic script, no judgment call, content never flows through the prompt).
- Relay the script's `SPLIT OK` / `SPLIT FAILED` / `SCRIPT_OK` output verbatim, per the source's Step 5/7.
- Backup-first behavior is unchanged; `/mempenny-restore` reverses any pass.
