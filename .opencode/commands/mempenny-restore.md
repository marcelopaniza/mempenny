---
description: Restore a memory-dir backup created by /mempenny-clean. Lists available backups, asks which one, takes a safety snapshot of the current state, then restores. (opencode host adapter)
agent: mempenny
---

# MemPenny restore — opencode host adapter

The user invoked this command with: $ARGUMENTS

Execute the MemPenny **restore** flow. The canonical procedure lives in:

    ${MEMPENNY_ROOT}/commands/restore.md

**Read it first with the Read tool** — it is the single source of truth for the backup-listing, safety-snapshot, and overwrite logic, plus the F-M2 symlink guard and L1 `chmod 600`. This file only describes the opencode host differences.

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

Apply F-M2 + L1 exactly as the source specifies.

### C. Command namespace
Sibling commands use the hyphen namespace: `/mempenny-clean`, `/mempenny-nap`, `/mempenny-memory-*`.

### restore-specific notes
- Positional arg is a backup name or the literal `latest`; `--dir` / `--lang` parse from `$ARGUMENTS` per the source Step 1.
- Restore is always safe by design (it snapshots current state before overwriting); no host-specific change to that contract.
