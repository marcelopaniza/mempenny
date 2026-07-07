---
description: One-shot memory cleanup — triage + apply in a single pass. First run asks where backups should live; subsequent runs reuse that folder automatically. (opencode host adapter)
agent: mempenny
---

# MemPenny clean — opencode host adapter

The user invoked this command with: $ARGUMENTS

Execute the MemPenny **clean** flow. The canonical procedure lives in:

    ${MEMPENNY_ROOT}/commands/clean.md

**Read it first with the Read tool** — it is the single source of truth for every step, guard, locale key, migration rule, and conservation check. The 4,000-line procedure lives there; this file only describes the opencode host differences.

While executing the source procedure, apply these **opencode host adaptations** (override the source wherever they conflict):

### A. Paths & environment
The env shim (`.opencode/plugins/mempenny-env.ts`) already sets `MEMPENNY_HOST=opencode`, `MEMPENNY_ROOT`, and `MEMPENNY_DATA_DIR`. Substitute every Claude Code env var in the source as follows:

- `${CLAUDE_PLUGIN_ROOT}` → `${MEMPENNY_ROOT}` (locales live at `${MEMPENNY_ROOT}/locales/<lang>/strings.json`)
- `${CLAUDE_PLUGIN_DATA}` → `${MEMPENNY_DATA_DIR}` (`~/.local/share/mempenny`)
- `${CLAUDE_PROJECT_DIR}` → the current working directory

### B. Config path (host-aware — shared with Claude Code)
1. If `${MEMPENNY_CONFIG_PATH}` is set → use it.
2. Else if `~/.claude/` exists → `~/.claude/mempenny.config.json` (shared — zero setup if you run both hosts).
3. Else → `~/.config/opencode/mempenny.config.json`.

Apply the source's F-M2 symlink guard and L1 `chmod 600` on every read/write of this path, exactly as written there.

### C. Auto-memory (Claude Code-only feature)
opencode has no auto-memory feature. **Skip the `~/.claude/settings.json` → `autoMemoryEnabled` detection and offer entirely.** Treat `auto_memory_now_on=false` and suppress the empty-dir signal that step would set.

### D. Subagents (opencode Task tool)
The source spawns subagents with Claude Code syntax. Use opencode's Task tool instead:

- `subagent_type: "explore"` (read-only) where the source says `Explore`.
- `subagent_type: "general"` where the source says `general-purpose`.
- Lowercase. Pass `description` + `prompt`.
- Leave `model` unset (inherit the host model) unless the user exported `MEMPENNY_TRIAGE_MODEL`, in which case pass that value as `model`.

### E. Command namespace
opencode uses the hyphen namespace. The sibling commands are `/mempenny-nap`, `/mempenny-restore`, `/mempenny-memory-triage`, `/mempenny-memory-apply`, `/mempenny-memory-distill`, `/mempenny-memory-curate`, `/mempenny-memory-shard-roll`.

### clean-specific notes
- Arguments (`--dir`, `--only`, `--lang`, `--reconfigure`, `--yes`) parse from `$ARGUMENTS` exactly as the source's Step 1 describes.
- `--yes` skips the apply confirmation gate; backup-first behavior is unchanged and `/mempenny-restore` reverses any pass.
- The source's strict output contracts (migration `MIGRATION APPLIED:` / `MIGRATION FAILED:`, write `WRITE OK:` / `WRITE FAILED:`) are byte-exact — reproduce them verbatim.
- **Prefer the custom tools for deterministic steps** (they collapse several shell calls into one verified operation, and the `mempenny` agent pre-approves them):
  - Backup step → call the `mempenny-backup` tool with `{memory_dir, backup_root}` instead of running the `mkdir + cp -a + chmod + sha256sum` bash by hand. It returns `{backup_path, manifest}`. The bash block in the source remains the authoritative spec of what the step does; fall back to it only if the tool is unavailable.
  - Config load → call the `mempenny-read-config` tool (no args) instead of the `jq` + symlink-check bash. It returns the parsed config (or `{missing: true}`).
  - The conservation check and the write/verify landing script **stay bash** — they are hardened (v1.1.4) and not re-implemented as tools.
