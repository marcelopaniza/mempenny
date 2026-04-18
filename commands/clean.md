---
description: One-shot memory cleanup — triage + apply in a single pass. First run asks where backups should live; subsequent runs reuse that folder automatically.
argument-hint: [--dir <path>] [--only <glob>] [--lang <code>] [--reconfigure]
---

Clean the auto-memory directory in a single pass: triage → show summary → apply (with backup). Saves the user's backup folder preference on first run so subsequent runs are one command.

## Step 1 — Parse arguments

The user invoked this command with: $ARGUMENTS

Parse optional arguments:

- `--dir <path>` — absolute path to the memory directory. If set, use verbatim; otherwise auto-detect the current project's memory dir (see Step 3).
- `--only <glob>` — scope filter (e.g., `--only project_*.md`). Default: every `.md` file directly under the memory dir. Multiple globs can be comma-separated.
- `--lang <code>` — output language. If not passed, check `MEMPENNY_LOCALE`. Default `en`.
- `--reconfigure` — ignore any saved backup folder and re-prompt the user. Useful if the saved path is wrong/moved.

## Step 2 — Load locale strings

**2a — Validate `<lang>` before reading (H2: path traversal guard)**

Before constructing the locale path, validate that `<lang>` matches the regex `^[a-zA-Z]{2,3}(-[A-Za-z0-9]{2,8})?$`. If it does not match, treat it exactly like a missing locale: silently reset `<lang>` to `en` and warn with `errors.locale_missing`.

Read `${CLAUDE_PLUGIN_ROOT}/locales/<lang>/strings.json`. Fall back to `en` if the file is missing (warn with `errors.locale_missing`).

You'll need `clean.*`, `triage.*`, `apply.*`, and `errors.*` keys.

## Step 3 — Locate the memory directory

**If `--dir <path>` was passed**, apply the following validation before using it. On any failure, print `errors.memory_dir_not_found` and STOP:

**Validate `--dir <path>` (C-class shell-injection guard):**
1. Regex: the candidate path must match `^/[A-Za-z0-9/_.\- ]{1,4096}$` (alphanumerics, slash, underscore, dot, hyphen, space only).
2. Realpath: run `realpath "<candidate>"` via Bash. Use the resolved value for all subsequent steps.
3. Depth: reject if the realpath equals `/` or has fewer than 2 path components.
4. Existence + not-a-symlink: `[ -d "$resolved" ] && [ ! -L "$resolved" ]`.

If all checks pass, use the resolved path as `{MEMORY_DIR}`. Verify it exists and contains `.md` files.

**Otherwise**, auto-detect `~/.claude/projects/<project-id>/memory/` from the current project's working directory mapping. If ambiguous, ask the user for the absolute path using `errors.memory_dir_not_found`.

Hold this as `{MEMORY_DIR}` for the rest of the flow.

## Step 4 — Load or create the config

**Config file location:** `~/.claude/mempenny.config.json`

**Schema:**

```json
{
  "backup_folder": "/absolute/path/to/backups",
  "version": 1
}
```

**Read logic:**

1. Use the Read tool on `~/.claude/mempenny.config.json`.
2. If the file exists AND `--reconfigure` was NOT passed, run the following **config validation checks (M1)**. If ANY check fails, warn the user and fall through to first-run setup as if `--reconfigure` were passed:
   - JSON must parse cleanly (if not → fall through).
   - `backup_folder` must be a string (not a number, null, array, or object).
   - `backup_folder` must match the regex `^/[^\x00\n]{1,4096}$` (absolute path, no NUL byte, no newline, max 4096 chars).
   - Run `realpath "{backup_folder}"` via Bash and verify the resolved value still starts with `/`.
   - Verify the resolved path is writable: `mkdir -p "{BACKUP_ROOT}" && touch "{BACKUP_ROOT}/.mempenny-write-test" && rm "{BACKUP_ROOT}/.mempenny-write-test"`.
   If all checks pass, use the **realpath-resolved** value as `{BACKUP_ROOT}` and skip to Step 5.
3. Otherwise, run the **first-run setup** below.

### First-run setup

Show the user the intro using locale keys:

```
{clean.first_run_header}

{clean.first_run_intro}
{clean.first_run_default}    ← substitute {default} with {MEMORY_DIR}.backups/
{clean.first_run_prompt}
```

The default suggestion is `<MEMORY_DIR>.backups/` — a sibling of the memory dir itself. It keeps backups colocated with what they back up, and you don't need to invent a new location.

Use the `AskUserQuestion` tool to get the answer. Present two options:
- `Use default` → resolves to `<MEMORY_DIR>.backups/`
- `Custom path` → free-text entry; the user types an absolute path

**If `AskUserQuestion` returns no answer (cancelled/dismissed), abort immediately without writing the config or modifying anything. Print a one-line "setup cancelled, nothing changed" message. (M3)**

**Validation for both the default and custom paths (C1 + H4):**

Apply all of the following checks. If any fail, show `errors.backup_folder_invalid` with the offending path and re-prompt (up to the existing 3-retry cap, then abort with a clear message).

1. **Regex gate:** the candidate path must match `^/[A-Za-z0-9/_.\- ]{1,4096}$` (alphanumerics, slash, underscore, dot, hyphen, space only). Reject anything else — this prevents shell-injection characters from reaching the `cp -a` in Step 9.
2. **Realpath:** run `realpath "<candidate>"` via Bash. Use the resolved value for all subsequent steps and store this in the config (never store a symlink path).
3. **Overlap check (H4):** reject if `realpath({BACKUP_ROOT})` has `realpath({MEMORY_DIR})` as a prefix, OR `realpath({MEMORY_DIR})` has `realpath({BACKUP_ROOT})` as a prefix. Shell check:
   ```bash
   case "$realpath_backup" in "$realpath_memory"/*) echo REJECT;; esac
   case "$realpath_memory" in "$realpath_backup"/*) echo REJECT;; esac
   ```
4. **Depth check:** reject if the realpath equals `/`, has fewer than 2 path components (i.e., the basename is empty after removing the leading slash), OR (if `$HOME` is set and non-empty) equals `realpath $HOME`, OR (if `EUID == 0`) starts with `/root/`. The `$HOME` guard is conditional on the variable being set to avoid false-matching empty strings.
5. **Writability:** `mkdir -p "{BACKUP_ROOT}" && touch "{BACKUP_ROOT}/.mempenny-write-test" && rm "{BACKUP_ROOT}/.mempenny-write-test"`.
6. **Parent exists:** `[ -d "$(dirname "$resolved")" ]` — reject if the parent directory does not exist. Backup root must be created as a single new directory under an existing parent; MemPenny will not create a multi-level tree (prevents world-readable intermediate dirs when umask != 077).

Once you have a valid `{BACKUP_ROOT}` (the realpath-resolved value):

1. Create the directory with `mkdir -p -m 700 "{BACKUP_ROOT}"` then `chmod 700 "{BACKUP_ROOT}"`. **(L1: restrict permissions)**
2. Write the config file with the Write tool:

```json
{
  "backup_folder": "{BACKUP_ROOT}",
  "version": 1
}
```

3. After writing the config, run `chmod 600 ~/.claude/mempenny.config.json` via Bash. **(L1)**
4. Confirm with `clean.config_saved` (substituting `{path}` with `~/.claude/mempenny.config.json`).

## Step 5 — Show the run context

Before doing anything destructive, print a 3-line context so the user knows exactly what they're about to clean:

```
{clean.memory_dir_label}:    {MEMORY_DIR}
{clean.backup_folder_label}: {BACKUP_ROOT}
{clean.running_triage}
```

## Step 6 — Run triage (dry run)

Spawn a triage subagent identical to `/mp:memory-triage` Step 5. Use:

- `subagent_type: Explore`
- `model: sonnet`
- `run_in_background: false`
- Prompt: the triage prompt block at the bottom of this file (it's the same triage logic).

Write the returned table to `/tmp/triage_table.md`.

## Step 7 — Show the summary

Print a short summary using `triage.*` labels (same format as `/mp:memory-triage` Step 6):

```
{triage.header}. {triage.table_path_label}: /tmp/triage_table.md

{triage.delete_label}:   N {triage.files_unit}, X KB
{triage.archive_label}:  N {triage.files_unit}, X KB
{triage.distill_label}:  N {triage.files_unit}, X KB → Y KB
{triage.keep_label}:     N {triage.files_unit}, X KB

{triage.total_before_label}: X KB
{triage.total_after_label}:  Y KB
{triage.net_savings_label}:  Z KB (W%)
```

Then show 3-5 high-confidence DELETE examples and 2-3 DISTILL examples (same as triage command).

## Step 8 — Confirm before applying

Unlike `/mp:memory-triage`, this command auto-applies — but only after the user explicitly approves. Use `AskUserQuestion`:

**Question:** "Apply these changes?"

**Options:**
- `Yes, apply` → proceed to Step 9
- `No, cancel` → STOP. Leave `/tmp/triage_table.md` in place so the user can review manually and run `/mp:memory-apply` later if they change their mind. Print a short "cancelled, nothing changed" message and exit.
- `Show full table` → Read `/tmp/triage_table.md` and print it verbatim, then re-ask the same question.

**TOCTOU re-check before handing off to Step 9 (M2):** Before spawning the apply subagent, re-verify `{BACKUP_ROOT}` in Bash:

```bash
# {BACKUP_ROOT} is the validated, realpath'd value from Step 4
[ -d "{BACKUP_ROOT}" ] && [ ! -L "{BACKUP_ROOT}" ] || { echo "ABORT: backup root missing or is a symlink"; exit 1; }
realpath_now=$(realpath "{BACKUP_ROOT}")
# Re-run H4 overlap check against current realpath of MEMORY_DIR
realpath_mem=$(realpath "{MEMORY_DIR}")
case "$realpath_now" in "$realpath_mem"/*) echo "ABORT: overlap"; exit 1;; esac
case "$realpath_mem" in "$realpath_now"/*) echo "ABORT: overlap"; exit 1;; esac
```

If either check fails, STOP. Do not spawn the subagent or modify any files.

## Step 9 — Apply with timestamped backup

Spawn the apply subagent (same as `/mp:memory-apply` Step 3), with one critical difference:

**Override the backup location.** The default apply subagent creates the backup at `{MEMORY_DIR}.backup-YYYYMMDD/` (sibling of memory dir). For `/mp:clean`, the backup goes inside the user-configured `{BACKUP_ROOT}` with a timestamp:

```
{BACKUP_ROOT}/memory.backup-YYYYMMDDHHMMSS/
```

Parameterize the apply subagent prompt with:
- `{TABLE_PATH}` = `/tmp/triage_table.md`
- `{MEMORY_DIR}` = the target memory dir
- `{BACKUP_PATH}` = `{BACKUP_ROOT}/memory.backup-$(date -u +%Y%m%d%H%M%S)-$$/`
  <!-- L2: UTC timestamp avoids timezone ambiguity; $$ (process ID) suffix prevents collision when two clean runs fire in the same second -->

The apply prompt (shown at the bottom of this file) uses `{BACKUP_PATH}` verbatim instead of building its own path. Everything else (DELETE/ARCHIVE/DISTILL/MEMORY.md update) is identical to `/mp:memory-apply`.

Tell the user before kicking off: `clean.auto_apply_note` with `{path}` = `{BACKUP_PATH}`.

Run in foreground; wait for the result.

## Step 10 — Report and hint at rollback

Render the result using `apply.*` labels (same shape as `/mp:memory-apply` Step 4). Then print:

```
{clean.done_header}

{clean.rollback_hint}   ← substitute {backup_name} with the basename of {BACKUP_PATH}
```

Do NOT print the long `rm -rf … && mv …` rollback snippet — that's what `/mp:restore` is for. Just point them there.

Then print this hard-coded line (L5 disk pruning reminder):

```
Backups accumulate over time. Run `ls {BACKUP_ROOT}` periodically and delete old backups you no longer need.
```

<!-- TODO: localize L5 pruning reminder — key suggestion: clean.backup_pruning_hint -->

Optionally, if `caveman:compress` is in the skills list, end with the next-step suggestion from `apply.next_step_suggestion` (substitute `{dir}` with `{MEMORY_DIR}`). If caveman is not installed, skip the suggestion silently (don't nag).

---

## Triage prompt (pass to the triage subagent in Step 6)

You're doing a **DRY-RUN** triage of a Claude Code auto-memory directory. We want to shrink it dramatically **without losing forward-looking truth**. No writes — your output is a proposal table for human review.

**Scope:** every `.md` file matching `{SCOPE_GLOB}` under `{MEMORY_DIR}`. Skip `MEMORY.md`, `*.original.md` backup files, and anything under `archive/`.

**Output language directive:** {DISTILL_OUTPUT_INSTRUCTION}

### Four possible actions per file

- **DELETE** — content is fully obsolete. Use only when at least one of:
  - Resolved bug whose fix is in the code (code is authoritative)
  - One-shot historical event with no future implication
  - Explicitly marked "RESOLVED" / "do not re-fix" / "Historical only"
  - Superseded by a newer file on the same topic
  - **Be conservative.** When unsure, prefer DISTILL.

- **ARCHIVE** — historical postmortem worth keeping for forensics but NOT daily lookup. Will be moved to `{MEMORY_DIR}/archive/` and removed from `MEMORY.md`.

- **DISTILL** — 1-3 load-bearing facts buried in prose. Provide the distilled replacement (max 3 sentences) in the table.

- **KEEP** — active state, architecture, recurring rule, or already-tight prose. If a KEEP candidate is >3 KB with narrative bloat, prefer DISTILL.

### Recognition heuristics

- Files dated `YYYYMMDD` documenting a one-day incident → usually DISTILL or ARCHIVE
- Files with "RESOLVED", "verified clean", "fixed in", "do not re-fix" → likely DELETE or ARCHIVE
- Architecture / service / protocol docs → KEEP
- Single test-run results → DISTILL to "what's now true"
- Files >5 KB with narrative prose → DISTILL aggressively

### Output format

One markdown table covering **every** file in scope, followed by a totals block.

```
| File | Size | Action | Reason (1 short line) | Distilled replacement (only if DISTILL) |
|---|---|---|---|---|
| foo_20260101.md | 6.2 KB | DISTILL | Dated test-run, fix is in code | Install pipeline works end-to-end as of 2026-01-01. Manual SOF firmware step still required. |
```

After the table:

```
DELETE:   N files, X KB freed
ARCHIVE:  N files, X KB freed (moved out of auto-load path)
DISTILL:  N files, X KB → Y KB (Z% reduction)
KEEP:     N files, X KB unchanged

Total before: X KB
Total after:  Y KB
Net savings:  Z KB (W%)
```

### Constraints

- Read every file before classifying it — don't classify from filename alone.
- Distilled replacements must be tight: 1-3 sentences, factual, forward-looking. Preserve any URLs, file paths, commands, or version numbers verbatim — **do not translate technical terms** even when the output language is not English.
- Preserve **"without loss"** as the top priority. Aggression is not a goal.
- Conservative with DELETE: when in doubt, ARCHIVE or DISTILL.
- Output the table + totals block. Nothing else.

---

## Apply prompt (pass to the apply subagent in Step 9)

You are applying a pre-approved memory triage plan. The plan is a markdown table at `{TABLE_PATH}` with columns:

`File | Size | Action | Reason | Distilled replacement (only if Action = DISTILL)`

**Target directory:** `{MEMORY_DIR}`
**Backup destination:** `{BACKUP_PATH}` — an absolute path. Create the parent if needed. Do NOT invent your own path.

### Actions

- **DELETE** — `rm` the file in the main dir
- **ARCHIVE** — `mv` the file into `{MEMORY_DIR}/archive/`
- **DISTILL** — preserve YAML frontmatter exactly, replace the body with the distilled replacement from the table, write back
- **KEEP** — skip, no action

### CRITICAL pre-step: backup (M6 — explicit ordering)

Before any modification, perform ALL three sub-steps in order. Proceed to Apply Order step 3 ONLY if all three pass.

```bash
set -euo pipefail
# {BACKUP_PATH} and {MEMORY_DIR} are validated, realpath'd, regex-gated paths — always double-quote on use

# Sub-step 1: create backup
mkdir -p "$(dirname "{BACKUP_PATH}")"
cp -a "{MEMORY_DIR}/" "{BACKUP_PATH}"
chmod 700 "{BACKUP_PATH}"  # L1.2: cp -a inherits source umask (often 755/775); tighten to 700
```

```bash
set -euo pipefail
# Sub-step 2: verify backup directory exists
[ -d "{BACKUP_PATH}" ] || { echo "ABORT: backup dir not created"; exit 1; }
```

```bash
set -euo pipefail
# Sub-step 3: verify file count matches source — only then proceed
SOURCE_COUNT=$(find "{MEMORY_DIR}" -type f | wc -l)
BACKUP_COUNT=$(find "{BACKUP_PATH}" -type f | wc -l)
[ "$SOURCE_COUNT" -eq "$BACKUP_COUNT" ] || { echo "ABORT: count mismatch source=$SOURCE_COUNT backup=$BACKUP_COUNT"; exit 1; }
```

If any sub-step fails, STOP immediately and return an error. Do NOT continue to Apply Order step 3.

### Apply order

1. Back up (as above — all three sub-steps must pass).
2. `mkdir -p {MEMORY_DIR}/archive/`.
3. For each DELETE row: verify the file still exists, then `rm` it. Track successes and failures.
4. For each ARCHIVE row: `mv` the file into `{MEMORY_DIR}/archive/`. Track successes and failures.
5. For each DISTILL row:
   - Read the file.
   - **If it starts with `---` YAML frontmatter**, preserve the frontmatter block character-for-character and replace the body (everything after the closing `---`) with the distilled replacement text from the table.
   - **Else if it starts with a `#` markdown heading line**, preserve that heading line and replace everything after it with the distilled replacement.
   - **Otherwise**, replace the entire file contents with the distilled replacement.
   - Keep a trailing newline in all three cases.
   - Write back with the Write tool.
6. Update `{MEMORY_DIR}/MEMORY.md`:
   - Remove any `- [filename.md](filename.md) - ...` line whose file was DELETED or ARCHIVED.
   - Leave DISTILLED entries alone — their description doesn't change just because the body shrank.
   - Preserve all section headers, even ones that become empty.

### Rollback policy

If ≥5% of actions in ANY bucket fail, STOP after that bucket and report. Do NOT auto-rollback — the user decides via `/mp:restore`.

### Idempotent semantics

If a DELETE target is already absent, or an ARCHIVE target is already in `archive/`, count that as a success. Do not error.

### Constraints

- Do not modify files outside `{MEMORY_DIR}`.
- Do not touch the backup after creation.
- Skip `MEMORY.md` itself, `*.original.md`, and anything under `archive/`.
- Files not mentioned in the table are skipped implicitly.

### Bash safety note

If you use a bash counter inside a loop while `set -e` is active, **do not** use `((count++))` — it exits 1 when the pre-increment value is 0, tripping `set -e`. Use `count=$((count+1))` instead.

### Return format

```
BACKUP: <path> (<N> files, verified)

DELETE:   <N>/<total> succeeded   [list any real failures with reason]
ARCHIVE:  <N>/<total> succeeded   [list any failures]
DISTILL:  <N>/<total> succeeded   [list any failures]

MEMORY.md:  <before> lines → <after> lines (<delta>)

Bytes:
  Main dir before:  X
  Main dir after:   Y   (excluding archive/)
  Archive:          Z
  Net savings:      W  (P%)

<warnings, if any>
```
