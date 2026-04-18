---
description: Apply a previously approved triage table to a Claude Code auto-memory directory. Creates a full backup first. Rolls back on failure.
argument-hint: [<path-to-table>] [--dir <path>] [--lang <code>]
---

Apply a pre-approved triage plan to a memory directory.

## Step 1 — Parse arguments

The user invoked this command with: $ARGUMENTS

- **Table path:** first positional argument, or default `/tmp/triage_table.md` if no argument given. Verify the file exists before continuing — if missing, report using the `errors.table_not_found` message from the loaded locale.
- **`--dir <path>`** — absolute path to the memory directory to apply against. **Critical**: if the triage was run with `--dir`, the apply **must** be run with the same `--dir` so the table lines up with the right target dir. If not set, auto-detect the current project's memory dir (same logic as `/memory-triage`).
- **`--lang <code>`** — language for the user-visible summary. If not passed, check `MEMPENNY_LOCALE`. Default `en`.

## Step 2 — Load locale strings

**2a — Validate `<lang>` before reading (H2: path traversal guard)**

Before constructing the locale path, validate that `<lang>` matches the regex `^[a-zA-Z]{2,3}(-[A-Za-z0-9]{2,8})?$`. If it does not match, treat it exactly like a missing locale: silently reset `<lang>` to `en` and warn with `errors.locale_missing`.

Read `${CLAUDE_PLUGIN_ROOT}/locales/<lang>/strings.json`. Fall back to `en` if missing (and warn using `errors.locale_missing`). You need `apply.*` labels for the final summary.

## Step 3 — Locate the memory directory and spawn the apply subagent

**If `--dir <path>` was passed in Step 1**, apply the following validation before using it. On any failure, print `errors.memory_dir_not_found` and STOP:

**Validate `--dir <path>` (C-class shell-injection guard):**
1. Regex: the candidate path must match `^/[A-Za-z0-9/_.\- ]{1,4096}$` (alphanumerics, slash, underscore, dot, hyphen, space only).
2. Realpath: run `realpath "<candidate>"` via Bash. Use the resolved value for all subsequent steps.
3. Depth: reject if the realpath equals `/` or has fewer than 2 path components.
4. Existence + not-a-symlink: `[ -d "$resolved" ] && [ ! -L "$resolved" ]`.

If all checks pass, use the resolved path as `{MEMORY_DIR}`. Otherwise, auto-detect `~/.claude/projects/<project-id>/memory/` from the current project (same logic as `/mp:memory-triage`).

**Compute the backup path (Issue D — unified convention):**

Before spawning the subagent, determine `{BACKUP_PATH}` as follows:

1. Attempt to read `~/.claude/mempenny.config.json`. If it exists and passes the same M1-class validation as `/mp:clean` Step 4 (JSON parses, `backup_folder` is a string matching `^/[^\x00\n]{1,4096}$`, realpath resolves and starts with `/`), set `{BACKUP_ROOT}` to the realpath'd `backup_folder` value. Additionally verify that the **parent** of `{BACKUP_ROOT}` exists: `[ -d "$(dirname "{BACKUP_ROOT}")" ]`. If the parent does not exist, treat the config as invalid and fall through to the legacy fallback (do not hard-abort — the intent is to keep things working). If the parent check passes, set `{BACKUP_PATH}` = `{BACKUP_ROOT}/memory.backup-$(date -u +%Y%m%d%H%M%S)-$$/`.
2. If the config does NOT exist or fails validation (including the parent-exists check above), fall back to the legacy sibling path with the same-day-overwrite bug fixed: `{BACKUP_PATH}` = `{MEMORY_DIR}.backup-$(date -u +%Y%m%d%H%M%S)-$$/`.

After computing `{BACKUP_PATH}` (either from config or fallback), verify it does NOT start with `{MEMORY_DIR}/`. Shell:
```bash
case "{BACKUP_PATH}" in "{MEMORY_DIR}"/*) echo "ABORT: backup path inside memory dir"; exit 1;; esac
```
This catches any path (including the fallback sibling case) that would cause a recursive backup.

Announce to the user which path was chosen before starting the backup:
- Config found: `Backup destination (from config): {BACKUP_PATH}`
- Fallback: `Backup destination (legacy sibling, no config found): {BACKUP_PATH}`

Ensure the parent directory exists: `mkdir -p -m 700 "$(dirname "{BACKUP_PATH}")"`.

**Spawn the apply subagent:**

Use the Agent tool with:

- `subagent_type: general-purpose` (needs Write/Edit/Bash)
- `model: sonnet` (mechanical execution)
- `prompt`: the apply prompt below, parameterized with `{TABLE_PATH}`, `{MEMORY_DIR}`, and `{BACKUP_PATH}`

Run in foreground — you need the result to show the user.

## Step 4 — Relay the result

When the subagent returns, render its results using the localized `apply.*` labels from `strings.json`. Example shape (substitute real values):

```
{backup_label}: <path> (<N> files, {backup_verified_suffix})

{delete_label}:   <N>/<total> {succeeded_label}
{archive_label}:  <N>/<total> {succeeded_label}
{distill_label}:  <N>/<total> {succeeded_label}

{memory_md_label}:  <before> → <after> {memory_md_lines_suffix} (<delta>)

{bytes_header}:
  {main_before_label}:  X
  {main_after_label}:   Y   ({main_after_suffix})
  {archive_label}:      Z
  {net_savings_label}:  W  (P%)
```

(Use the `triage.*` keys — `delete_label`, `archive_label`, `distill_label` — since the apply summary reuses the same bucket names.)

End with the rollback instructions in a code block so the user can copy-paste if needed. Use `apply.rollback_comment` as the comment line. Substitute `<BACKUP_PATH>` with the actual `{BACKUP_PATH}` used:

```
# {rollback_comment}
rm -rf "<MEMORY_DIR>/"
mv "<BACKUP_PATH>" "<MEMORY_DIR>/"
```

(If the backup went to `{BACKUP_ROOT}` from config, the user can also run `/mp:restore` to pick it interactively.)

After the rollback block, print the localized **next-step suggestion** from `apply.next_step_header` and `apply.next_step_suggestion`, substituting `{dir}` with the target directory. Example (en):

```
**Next step**

Run `/mp:memory-compress --dir <MEMORY_DIR>` to compress the surviving prose with caveman (if installed). MemPenny removes what shouldn't be there; caveman shrinks what's left.
```

This is a suggestion, not an automatic action. The user runs compress when ready. If they don't have caveman, `/mp:memory-compress` will detect that and print install instructions rather than modifying anything.

---

## Apply prompt (pass to the subagent)

You are applying a pre-approved memory triage plan. The plan is a markdown table at `{TABLE_PATH}` with columns:

`File | Size | Action | Reason | Distilled replacement (only if Action = DISTILL)`

**Target directory:** `{MEMORY_DIR}`
**Backup destination:** `{BACKUP_PATH}` — an absolute path computed and announced by the outer command in Step 3. Do NOT invent your own path.

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
2. `mkdir -p "{MEMORY_DIR}/archive/"`.
3. For each DELETE row in the table: verify the file still exists, then `rm` it. Track successes and failures.
4. For each ARCHIVE row: `mv` the file into `"{MEMORY_DIR}/archive/"`. Track successes and failures.
5. For each DISTILL row:
   - Read the file.
   - **If it starts with `---` YAML frontmatter**, preserve the frontmatter block character-for-character and replace the body (everything after the closing `---`) with the distilled replacement text from the table.
   - **Else if it starts with a `#` markdown heading line**, preserve that heading line and replace everything after it with the distilled replacement text. This keeps the file's title visible when the original author used a markdown heading instead of frontmatter.
   - **Otherwise**, replace the entire file contents with the distilled replacement text.
   - Keep a trailing newline in all three cases.
   - Write back with the Write tool.
6. Update `{MEMORY_DIR}/MEMORY.md`:
   - Remove any `- [filename.md](filename.md) - ...` line whose file was DELETED or ARCHIVED.
   - Leave DISTILLED entries alone — their description doesn't change just because the body shrank.
   - Preserve all section headers, even ones that become empty.

### Rollback policy

If ≥5% of actions in ANY bucket fail, STOP after that bucket and report. Do NOT auto-rollback — the user decides whether to restore from backup.

### Idempotent semantics

If a DELETE target is already absent, or an ARCHIVE target is already in `archive/`, count that as a success (the intent is satisfied). Do not error.

### Constraints

- Do not modify files outside `{MEMORY_DIR}`.
- Do not touch the backup after creation.
- Skip `MEMORY.md` itself, `*.original.md`, and anything under `archive/` — none of those appear in the table.
- Files with prefixes the table doesn't mention (`feedback_*.md`, `user_*.md`, etc.) are skipped implicitly — they simply don't appear in the table.

### Bash safety note

If you use a bash counter inside a loop while the script has `set -e` active (explicit or via shopt), **do not** use `((count++))` — it exits with code 1 when the pre-increment value is 0, which trips `set -e` and aborts the loop. Use `count=$((count+1))` instead, which always exits 0. This applies to any success/failure tallies you build during the DELETE / ARCHIVE / DISTILL passes.

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

(The outer `/memory-apply` command will re-render these labels in the user's locale before showing to the user — your subagent output can stay in English.)
