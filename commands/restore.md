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

**F-M2 + F2-M3 — symlink guard first** (stdout sentinel):
```bash
if [ -L ~/.claude/mempenny.config.json ]; then
  echo "MEMPENNY_CONFIG_INVALID=symlink"
fi
```
If the block prints `MEMPENNY_CONFIG_INVALID=symlink`, STOP with `restore.no_config`. A symlink'd config is suspicious (an attacker may have redirected it); refuse to restore anything until the user investigates. Unlike `/mp:clean` (which falls through to first-run setup), `/mp:restore` has no safe fallback — aborting is correct.

Otherwise, Read `~/.claude/mempenny.config.json`. It must contain `backup_folder`.

If the file does not exist, print `restore.no_config` and STOP. The user has never run `/mp:clean`, so there's nothing to restore.

**Config validation (M1 + C1 — parallel to clean.md Step 4):** If the file exists, run ALL of the following checks. If ANY check fails, print `restore.no_config` and STOP — do not continue with an untrustworthy path:

1. JSON must parse cleanly.
2. `backup_folder` must be a string (not a number, null, array, or object).
3. `backup_folder` must match the regex `^/[A-Za-z0-9/_.\- ]{1,4096}$` — the same tight regex as `--dir` validation. **C1 fix:** an earlier version used `^/[^\x00\n]{1,4096}$` which permitted shell metacharacters; a tampered config like `"backup_folder": "/tmp/x$(cmd)"` would have fired command substitution during the subsequent `realpath` call (double-quotes don't prevent `$(…)`). Reject such paths before any bash interpolation.
4. Run `realpath "{backup_folder}"` via Bash (safe now that the regex is tight) and verify the resolved value still starts with `/` AND still matches the same tight regex.

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

**Regardless of whether the path came from `--dir` or auto-detection, apply checks 1-3 of the validation block above before using it as `{MEMORY_DIR}` (H5).** For restore, check 4 is conditional (directory may not exist yet), but checks 1-3 (regex, realpath, depth) must pass. If validation fails on the auto-detected path, print `errors.memory_dir_not_found` and STOP.

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

**F2-L2 — pre-everything TOCTOU re-check** (F4-M1: moved ahead of the integrity check so a symlink-swap attack is caught before we waste a verification pass on attacker-controlled content). Step 6 validated the backup dir as a non-symlink, but the user's confirm prompt (Step 7) creates a window during which an attacker with write access to `{BACKUP_ROOT}` could swap the dir for a symlink pointing at a staged dir with a matching MANIFEST. Re-assert FIRST:

```bash
[ -L "{BACKUP_ROOT}/{chosen-name}" ] && { echo "ABORT (pre-restore TOCTOU): backup became a symlink"; exit 1; }
[ -d "{BACKUP_ROOT}/{chosen-name}" ] || { echo "ABORT: backup dir missing"; exit 1; }
```

**M4 + F-M3 — backup integrity check (runs AFTER F2-L2, so we know we're in a real dir; skipped silently for old backups without MANIFEST.sha256). Subshell-wrapped (F2-M1+F2-M2) so the `cd` is auto-scoped and temp files are cleaned up via `trap EXIT` even when `set -e` trips mid-block:**

```bash
# F3-L1: reject a MANIFEST.sha256 that is itself a symlink before using it.
# [ -f ] follows symlinks; [ ! -L ] rejects them. Both guards together mean
# "present AND not a symlink".
if [ -f "{BACKUP_ROOT}/{chosen-name}/MANIFEST.sha256" ] \
   && [ ! -L "{BACKUP_ROOT}/{chosen-name}/MANIFEST.sha256" ]; then
  (
    set -euo pipefail
    tmp_manifest=$(mktemp) tmp_actual=$(mktemp)
    trap 'rm -f "$tmp_manifest" "$tmp_actual"' EXIT
    cd "{BACKUP_ROOT}/{chosen-name}"

    # (1) Every file listed in MANIFEST must match its recorded hash (M4)
    sha256sum -c --quiet MANIFEST.sha256 \
      || { echo "ABORT: backup integrity check failed — files do not match recorded hashes"; exit 1; }

    # (2) No files outside MANIFEST (F-M3 — detect ADDED files)
    awk '{ sub(/^[^ ]+  /, ""); print }' MANIFEST.sha256 | sort > "$tmp_manifest"
    find . -type f ! -name MANIFEST.sha256 | sort > "$tmp_actual"
    if ! diff -q "$tmp_manifest" "$tmp_actual" > /dev/null; then
      echo "ABORT: backup contains files not in MANIFEST — possible tampering. Diff:"
      diff "$tmp_manifest" "$tmp_actual" || true
      exit 1
    fi
  ) || exit 1
fi
```

If either check fails, STOP — do not restore tampered files. User must investigate manually. (Old backups created before v0.4.1 have no manifest; integrity check is silently skipped for them, matching the v0.4.0 behavior they were created under.)

**Trust bound:** the MANIFEST file itself is co-located with the backup. An attacker with full write access to the backup dir can modify both the manifest and the files and keep them consistent. The integrity check defends against accidental corruption and *partial* tampering (modified-or-added files where the attacker forgot to rewrite MANIFEST). It does not defend against a complete rewrite — that's what backup dir `chmod 700` is for.

**F3-M2 — verification-time-vs-restore-time TOCTOU (acknowledged residual risk):** the integrity check above captures the backup's state at the moment of verification. Between that check and the `cp -a` below, an attacker who retains write access to `{BACKUP_ROOT}` can modify files in place — the cp then copies the tampered state. F2-L2's pre-everything symlink re-check (above) closes only the symlink-swap corner of this window, not contents modification. The TOCTOU is bounded by backup-dir `chmod 700` (only the owner can write), so this is effectively a self-attack or a post-compromise persistence primitive, not a primary attack vector. A proper fix (v0.5 roadmap) is a staging-area pattern: `cp backup → staging`, verify in the staging area, then `mv` staging into MEMORY_DIR atomically. For v0.4.1 this gap is left documented rather than redesigned.

**F2-L2 (suspenders) + copy — MUST run in the same bash invocation.** Duplicates the pre-integrity check above. Belt+suspenders: the first F2-L2 closes the symlink-swap window between Step 6 validation and integrity verification; this second one closes the window between integrity verification and `cp -a`. Without this re-check, an attacker could swap `{BACKUP_ROOT}/{chosen-name}` for a symlink between integrity and cp, and `cp -a` would follow it (`-a` preserves symlink-ness of sources it encounters, but the top-level argument with a trailing `/` is dereferenced by cp). **The check and the cp are one bash block so the interval between them is microseconds in the same shell — do not split them into two Bash tool invocations.** All paths are quoted. `{chosen-name}` was already validated by the Step 6 block (matches `^memory\.backup-[0-9]{14}(-[0-9]+)?$`, no `/` or `..`, realpath is a direct non-symlink child of `{BACKUP_ROOT}`).

```bash
set -euo pipefail
[ -L "{BACKUP_ROOT}/{chosen-name}" ] && { echo "ABORT (pre-cp TOCTOU): backup became a symlink after integrity check"; exit 1; }
[ -d "{BACKUP_ROOT}/{chosen-name}" ] || { echo "ABORT: backup dir missing"; exit 1; }
cp -a "{BACKUP_ROOT}/{chosen-name}/" "{MEMORY_DIR}/"
```

`cp -a` (archive mode) preserves permissions, timestamps, and symlinks-as-symlinks for anything INSIDE the backup. Backup contents are part of the F3-M2 acknowledged residual (an attacker with write on `{BACKUP_ROOT}` can tamper in place between verification and cp); the symlink re-check above only closes the specific sub-case where the top-level directory entry itself is swapped for a symlink.

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

Print the localized `restore.safety_retention_hint` (substituting `{memory_dir}` with `{MEMORY_DIR}`).

---

## Constraints

- Never delete the backup in `{BACKUP_ROOT}` — restore is a copy, not a move. Users may want to restore the same backup again.
- Never touch anything outside `{BACKUP_ROOT}`, `{MEMORY_DIR}`, or the safety snapshot path.
- If the chosen backup path fails any check in the Step 6 validation block (regex, no-traversal, realpath child check, symlink check), STOP — treat as tampering. Those four checks are the concrete definition of "outside `{BACKUP_ROOT}`".
- Do not modify `~/.claude/mempenny.config.json` during restore.
