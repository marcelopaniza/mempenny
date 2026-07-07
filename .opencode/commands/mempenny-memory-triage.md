---
description: Dry-run triage of an auto-memory directory. Produces a markdown table of proposed actions (delete / archive / distill / keep). No writes. (opencode host adapter)
agent: mempenny
---

# MemPenny memory-triage — opencode host adapter

The user invoked this command with: $ARGUMENTS

Execute the MemPenny **memory-triage** flow. The canonical procedure lives in:

    ${MEMPENNY_ROOT}/commands/memory-triage.md

**Read it first with the Read tool** — it is the single source of truth for the dry-run discipline, the 4-action vocabulary (DELETE / ARCHIVE / DISTILL / KEEP), the prompt-injection guard (H2), and the output table schema. This file only describes the opencode host differences.

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
The source spawns the triage as `subagent_type: Explore`. On opencode use `subagent_type: "explore"` (read-only), lowercase, passing `description` + `prompt`. Leave `model` unset unless `MEMPENNY_TRIAGE_MODEL` is exported.

### D. Command namespace
Sibling commands use the hyphen namespace: `/mempenny-clean`, `/mempenny-nap`, `/mempenny-restore`, `/mempenny-memory-apply`, `/mempenny-memory-distill`, `/mempenny-memory-curate`, `/mempenny-memory-shard-roll`.

### triage-specific notes
- `--dir`, `--only`, `--lang` parse from `$ARGUMENTS` per the source Step 1.
- The source's output contract is already strict — **one markdown table + the totals block, nothing else, no prose before or after.** Reproduce it exactly; do not invent a different schema or add a confidence column.
- The per-invocation `mktemp` table path (H3) is what the user passes to `/mempenny-memory-apply` — surface it prominently, exactly as the source does.
