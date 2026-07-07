---
description: Schedule /mempenny-clean to run daily, weekly, or once. Fires the next time you open opencode in this project after the scheduled time, via a desktop notification. (opencode host adapter)
agent: mempenny
---

# MemPenny nap — opencode host adapter

The user invoked this command with: $ARGUMENTS

Execute the MemPenny **nap** (schedule) flow. The canonical procedure lives in:

    ${MEMPENNY_ROOT}/commands/nap.md

**Read it first with the Read tool** — it is the single source of truth for the schedule schema, the config upsert discipline, the symlink guard, and `chmod 600`. This file only describes the opencode host differences.

While executing the source procedure, apply these **opencode host adaptations** (override the source wherever they conflict):

### A. Paths & environment
The env shim sets `MEMPENNY_HOST=opencode`, `MEMPENNY_ROOT`, `MEMPENNY_DATA_DIR`. Substitute:

- `${CLAUDE_PLUGIN_ROOT}` → `${MEMPENNY_ROOT}`
- `${CLAUDE_PLUGIN_DATA}` → `${MEMPENNY_DATA_DIR}`
- `${CLAUDE_PROJECT_DIR}` → the current working directory

### B. Config path (shared with Claude Code)
Same host-aware rule as the other commands:

1. `${MEMPENNY_CONFIG_PATH}` if set.
2. Else `~/.claude/mempenny.config.json` if `~/.claude/` exists.
3. Else `~/.config/opencode/mempenny.config.json`.

Apply F-M2 + L1 exactly as the source specifies.

### C. Auto-memory (Claude Code-only)
Skip the `~/.claude/settings.json` → `autoMemoryEnabled` subroutine entirely; opencode has no equivalent.

### D. Where the schedule fires
The source (nap.md) says the cleanup fires via a plugin-shipped `SessionStart` hook the next time you open Claude Code. On opencode the equivalent is the TS plugin at `.opencode/plugins/mempenny-nap.ts`, which subscribes to opencode's `session.created` event.

**v1.2 is notify-only:** when a nap comes due, the plugin shows a desktop notification telling you to run `/mempenny-clean --yes`. It does not auto-invoke the cleanup (that is reserved for a future opencode SDK command-invoke path). So after scheduling, the next-time-you-open behavior is: you get notified, you run `/mempenny-clean --yes` yourself.

### E. Command namespace
Sibling commands use the hyphen namespace: `/mempenny-clean`, `/mempenny-restore`, `/mempenny-memory-*`.

### nap-specific notes
- `--cancel` / `--list` / `--dir` / `--lang` parse from `$ARGUMENTS` per the source Step 1.
- The schedule row you write (`frequency`, `time`) is read by `mempenny-nap.ts` verbatim — keep the same field names and the `daily|weekly|once` + `HH:MM` formats the source specifies.
- An optional `mode` field is read by the plugin (`"notify"` default; `"auto"` reserved for future). Do not advertise `auto` to the user yet.
