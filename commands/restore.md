---
description: Restore a memory-dir backup created by /mp:clean. Lists available backups, asks which one, takes a safety snapshot of the current state, then restores.
argument-hint: [<backup-name>|latest] [--dir <path>] [--lang <code>]
---

Restore a previously-taken memory backup. Safe by default: always takes a timestamped snapshot of the current memory dir before overwriting, so a bad restore is itself reversible.

## Step 1 — Parse arguments

The user invoked this command with: $ARGUMENTS

- **Positional arg** — a specific backup name (e.g., `memory.backup-20260417143052`) OR the literal word `latest`. If omitted, we'll list backups and prompt the user interactively.
- `--dir <path>` — absolute path to the memory directory to restore INTO. If not set, auto-detect the current project's memory dir (same logic as `/mp:clean`).
- `--lang <code>` — output language. Defaults to `MEMPENNY_LOCALE` or `en`.

## Step 2 — Load locale strings

**2a — Validate `<lang>` before reading (H2: path traversal guard)**

Before constructing the locale path, validate that `<lang>` matches the regex `^[a-zA-Z]{2,3}(-[A-Za-z0-9]{2,8})?$`. If it does not match, treat it exactly like a missing locale: silently reset `<lang>` to `en` and warn with `errors.locale_missing`.

Read `${CLAUDE_PLUGIN_ROOT}/locales/<lang>/strings.json`. Fall back to `en` if the file is missing (warn with `errors.locale_missing`). You need `restore.*` and `errors.*` keys.

## Step 3 — Read the config

Read `~/.claude/mempenny.config.json`. It must contain `backup_folder`.

If the file does not exist, print `restore.no_config` and STOP. The user has never run `/mp:clean`, so there's nothing to restore.

**Config validation (M1 — parallel to clean.md Step 4):** If the file exists, run ALL of the following checks. If ANY check fails, print `restore.no_config` and STOP — do not continue with an untrustworthy path:

1. JSON must parse cleanly.
2. `backup_folder` must be a string (not a number, null, array, or object).
3. `backup_folder` must match the regex `^/[^\x00\n]{1,4096}$` (absolute path, no NUL byte, no newline, max 4096 chars).
4. Run `realpath "{backup_folder}"` via Bash and verify the resolved value still starts with `/`.

Hold the **realpath-resolved** value as `{BACKUP_ROOT}`.

## Step 4 — Locate the target memory directory

**If `--dir <path>` was passed**, apply the following validation before using it. On any failure, print `errors.memory_dir_not_found` and STOP:

**Validate `--dir <path>` (C-class shell-injection guard):**
1. Regex: the candidate path must match `^/[A-Za-z0-9/_.\- ]{1,4096}$` (alphanumerics, slash, underscore, dot, hyphen, space only).
2. Realpath: run `realpath "<candidate>"` via Bash. Use the resolved value for all subsequent steps.
3. Depth: reject if the realpath equals `/` or has fewer than 2 path components.
4. Existence + not-a-symlink: `[ -d "$resolved" ] && [ ! -L "$resolved" ]`. (It's OK if the directory does not exist yet — restore will create it. Skip check 4 if the path does not exist, but still apply checks 1–3.)

If all checks pass, use the resolved path as `{MEMORY_DIR}`.

**Otherwise**, auto-detect `~/.claude/projects/<project-id>/memory/`.

Hold as `{MEMORY_DIR}`. It's OK if it doesn't exist yet — restore will create it.

## Step 5 — List available backups

Use Bash to list backups:

```bash
if [ ! -d "{BACKUP_ROOT}" ]; then
  # print restore.no_backups_found with {path}={BACKUP_ROOT} and STOP
fi
ls -1dt -- "{BACKUP_ROOT}/"memory.backup-* 2>/dev/null
```

The `-t` flag sorts newest first. Each line is one backup directory. Valid backup names match `^memory\.backup-[0-9]{14}(-[0-9]+)?$` — the optional `-[0-9]+` suffix is a PID added by `/mp:clean` hardening.

For each backup, capture:
- **name** — basename (e.g., `memory.backup-20260417143052` or `memory.backup-20260417143052-12345`)
- **size** — `du -sh "{BACKUP_ROOT}/<name>"` human-readable
- **date** — parse the 14-digit timestamp from the name (format: `YYYYMMDDHHMMSS`) and format as ISO-ish `YYYY-MM-DD HH:MM:SS`. If parsing fails (non-standard name), fall back to `stat`-based mtime.

If the directory exists but the glob returns no results, print `restore.no_backups_found` with `{path}` = `{BACKUP_ROOT}` and STOP.

## Step 6 — Pick a backup

**Name validation block (C2 — applies regardless of how the name was obtained):**

Before using any chosen name downstream, run ALL of the following checks. If any fail, print `errors.backup_not_found` with `{name}` = the value and STOP — do NOT continue to Step 7.

1. **Regex:** the name must match `^memory\.backup-[0-9]{14}(-[0-9]+)?$` (14-digit timestamp, optional numeric PID suffix). No other characters permitted.
2. **No traversal:** the name must NOT contain `/`, `\`, or `..`.
3. **Realpath child check:**
   ```bash
   resolved=$(realpath "{BACKUP_ROOT}/{chosen-name}" 2>/dev/null)
   root_resolved=$(realpath "{BACKUP_ROOT}" 2>/dev/null)
   case "$resolved" in "$root_resolved"/*) ;; *) echo REJECT;; esac
   ```
   The resolved path must be a direct child of `{BACKUP_ROOT}`.
4. **Symlink + directory check (H1):**
   ```bash
   [ -d "$resolved" ] && [ ! -L "$resolved" ] || echo REJECT
   ```
   The target must be a real directory, not a symlink.

**If a positional argument was passed:**

- If it's `latest`, pick the first entry in the sorted list.
- Otherwise, it's treated as a backup name:
  - Apply the validation block above first.
  - Then match exactly against basenames in the list.
  - If no match, print `errors.backup_not_found` with `{name}` = the argument and STOP.

Skip to Step 7.

**If no positional arg:**

Print the list using `restore.header` and `restore.backup_entry` (substitute `{index}`, `{name}`, `{size}`, `{date}`):

```
{restore.header}

1. memory.backup-20260417143052  (1.2 MB, 2026-04-17 14:30:52)
2. memory.backup-20260417091408  (1.4 MB, 2026-04-17 09:14:08)
3. memory.backup-20260416235700  (1.5 MB, 2026-04-16 23:57:00)
```

Use `AskUserQuestion` to prompt with `restore.pick_prompt`. Options:
- The top **10** backups as fixed options (labeled by name + date).
- A fixed option `Cancel` that aborts — print `restore.cancelled` and STOP.
- A fixed option `Show all / specify by name` — if selected, print the full backup list and instruct the user to re-invoke with the chosen name as a positional arg (e.g., `/mp:restore memory.backup-20260417143052`). Do NOT attempt free-text entry — `AskUserQuestion` is options-only.

Apply the validation block above to whatever name is ultimately chosen.

## Step 7 — Confirm

Build the confirm block using `restore.*` keys:

```
{restore.confirm_header}

{restore.confirm_from}    ← {backup} = {BACKUP_ROOT}/<chosen-name>
{restore.confirm_to}      ← {target} = {MEMORY_DIR}

{restore.confirm_safety}  ← {safety} = {MEMORY_DIR}.pre-restore-YYYYMMDDHHMMSS/
```

`AskUserQuestion` with `restore.confirm_prompt`. Two options:
- `Yes, restore` → proceed to Step 8
- `No, cancel` → print `restore.cancelled` and STOP

## Step 8 — Take a safety snapshot of current state

Before overwriting, snapshot the current memory dir so the restore itself is reversible:

```bash
set -euo pipefail
SAFETY="{MEMORY_DIR}.pre-restore-$(date -u +%Y%m%d%H%M%S)-$$"
if [ -e "{MEMORY_DIR}" ]; then
  mv "{MEMORY_DIR}" "$SAFETY" || { echo "safety snapshot failed"; exit 1; }
  [ -d "$SAFETY" ] || { echo "safety snapshot verification failed"; exit 1; }
fi
```

If `{MEMORY_DIR}` doesn't exist (e.g., user wiped it themselves), skip the `mv` and don't create an empty snapshot — just proceed. If the `mv` fails for any reason (cross-filesystem, permissions, etc.), the script exits immediately and Step 9 does NOT run.

## Step 9 — Restore

**L3 assertion — verify safety snapshot succeeded:**

```bash
[ ! -e "{MEMORY_DIR}" ] || { echo "memory dir unexpectedly present after safety mv"; exit 1; }
```

This fires at the very start of Step 9 before any write. If `{MEMORY_DIR}` still exists at this point, something went wrong in Step 8 — abort immediately.

Copy the backup into place:

```bash
cp -a "{BACKUP_ROOT}/{chosen-name}/" "{MEMORY_DIR}/"
```

Use `cp -a` (archive mode) so permissions/timestamps are preserved. All paths are quoted. `{chosen-name}` has already been validated by the Step 6 block — it matches `^memory\.backup-[0-9]{14}(-[0-9]+)?$`, contains no `/` or `..`, and its realpath was confirmed to be a direct non-symlink child of `{BACKUP_ROOT}`.

Verify by comparing file counts AND print the resolved source and destination paths so the user can audit:

```bash
SRC_RESOLVED=$(realpath "{BACKUP_ROOT}/{chosen-name}")
DST_RESOLVED=$(realpath "{MEMORY_DIR}")
echo "Source:      $SRC_RESOLVED"
echo "Destination: $DST_RESOLVED"

BACKUP_COUNT=$(find "{BACKUP_ROOT}/{chosen-name}" -type f | wc -l)
RESTORED_COUNT=$(find "{MEMORY_DIR}" -type f | wc -l)
```

If counts don't match, leave the safety snapshot in place and print a loud warning:

```
WARNING: file count mismatch — backup had $BACKUP_COUNT files, restored dir has $RESTORED_COUNT.
The safety snapshot is at $SAFETY — inspect manually before deleting it.
Do NOT run /mp:restore again until you have verified the state.
```

Then STOP (do not print the normal Step 10 completion message).

## Step 10 — Report

Print:

```
{restore.restore_complete}       ← {backup} = <chosen-name>, {target} = {MEMORY_DIR}
{restore.safety_snapshot_note}   ← {safety} = path from Step 8 (omit this line if Step 8 skipped)
```

<!-- TODO: localize L5 retention reminder -->
Safety snapshots accumulate over time. Run `ls -d {MEMORY_DIR}.pre-restore-*` periodically to see them; delete ones older than ~2 weeks if nothing feels wrong.

---

## Constraints

- Never delete the backup in `{BACKUP_ROOT}` — restore is a copy, not a move. Users may want to restore the same backup again.
- Never touch anything outside `{BACKUP_ROOT}`, `{MEMORY_DIR}`, or the safety snapshot path.
- If the chosen backup path fails any check in the Step 6 validation block (regex, no-traversal, realpath child check, symlink check), STOP — treat as tampering. Those four checks are the concrete definition of "outside `{BACKUP_ROOT}`".
- Do not modify `~/.claude/mempenny.config.json` during restore.
