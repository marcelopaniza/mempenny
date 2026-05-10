---
description: Schedule /mempenny:clean to run daily, weekly, or once. Fires the next time you open Claude Code in this project after the scheduled time. Uses Claude credits per run.
argument-hint: [--cancel] [--list] [--dir <path>] [--lang <code>]
---

Schedule a recurring `/mempenny:clean` for the current memory directory. The schedule lives in `~/.claude/mempenny.config.json`; the cleanup itself fires via a plugin-shipped `SessionStart` hook the next time you open Claude Code in this project after the scheduled time.

**Auth-agnostic:** works with whatever Claude Code is already using — OAuth, API key, otherwise. MemPenny doesn't care.

## Step 1 — Parse arguments

The user invoked this command with: $ARGUMENTS

Parse optional arguments:

- `--cancel` — remove the schedule entry for the current memory dir. Mutually exclusive with the configure flow.
- `--list` — print all scheduled memory dirs from the config and exit. Read-only.
- `--dir <path>` — absolute path to the memory directory. If set, use verbatim; otherwise auto-detect (Step 3).
- `--lang <code>` — output language. If not passed, check `MEMPENNY_LOCALE`. Default `en`.

If both `--cancel` and `--list` are passed, treat as `--list` (read-only wins; cancel is ignored). If `--list` is passed, skip Step 3's memory-dir resolution — `--list` is global.

## Step 2 — Load locale strings

**2a — Validate `<lang>` before reading (H2: path traversal guard)**

Before constructing the locale path, validate that `<lang>` matches the regex `^[a-zA-Z]{2,3}(-[A-Za-z0-9]{2,8})?$`. If it does not match, treat it exactly like a missing locale: silently reset `<lang>` to `en` and warn with `errors.locale_missing`.

Read `${CLAUDE_PLUGIN_ROOT}/locales/<lang>/strings.json`. Fall back to `en` if the file is missing (warn with `errors.locale_missing`).

You'll need `nap.*`, `errors.*`, `warnings.*`, `prompts.*`, `confirmations.*`, and `clean.first_run_default` keys.

## Step 3 — Locate the memory directory

(Skip this step if `--list` was passed — `--list` is global across all configured memory dirs.)

**If `--dir <path>` was passed**, apply the following validation. On any failure, print `errors.memory_dir_not_found` and STOP:

1. Regex: `^/[A-Za-z0-9/_.\- ]{1,4096}$` (alphanumerics, slash, underscore, dot, hyphen, space only).
2. Realpath: run `realpath "<candidate>"` via Bash. Use the resolved value for all subsequent steps.
3. Depth: reject if the realpath equals `/` or has fewer than 2 path components.
4. Existence + not-a-symlink: `[ -d "$resolved" ] && [ ! -L "$resolved" ]`.

**Otherwise**, auto-detect `~/.claude/projects/<project-id>/memory/` from the current project's working directory mapping. If ambiguous, ask the user for the absolute path using `errors.memory_dir_not_found`.

**Apply the 4-check validation block above to the auto-detected path as well (H5).** If validation fails, print `errors.memory_dir_not_found` and STOP.

**Soft warn if memory directory is under `/tmp` or `/var/tmp` (H5 post-check):**

```bash
case "$resolved" in
  /tmp/*|/tmp|/var/tmp/*|/var/tmp)
    print warnings.memory_dir_in_tmp (substituting {path} with $resolved)
    # PROCEED — warning only; scheduling nap for a volatile dir is allowed
    ;;
esac
```

**Lock-marker check (hard abort):**

```bash
for marker in ".mempenny-lock" ".mempenny-fixture"; do
  if [ -L "$resolved/$marker" ] || [ -e "$resolved/$marker" ]; then
    # Print errors.dir_locked (substituting {path} with $resolved and {marker} with $marker)
    print errors.dir_locked
    exit / STOP
  fi
done
```

If a file or directory or symlink at either marker path exists at the resolved memory dir, print `errors.dir_locked` (substituting `{path}` with `$resolved` and `{marker}` with `$marker`) and STOP. No schedule write, no config write — the directory is off-limits.

**If `--cancel` was NOT passed, run the auto-memory state detection below. (Skip on `--cancel` — the user is removing a schedule, not configuring one.)**

**Auto-memory state detection (H5 post-check):**

Check whether Claude Code's auto-memory feature is enabled. If off, offer to turn it on for the user — they're configuring a recurring clean, which only matters if auto-memory loads what's left.

    ```bash
    auto_memory_off_reason=""
    auto_memory_off_path=""

    # 1. Env var override beats everything
    if [ "${CLAUDE_CODE_DISABLE_AUTO_MEMORY:-}" = "1" ]; then
      auto_memory_off_reason="env"
      auto_memory_off_path="CLAUDE_CODE_DISABLE_AUTO_MEMORY=1"
    fi

    # 2. Settings layers (only if env var didn't already set off).
    # Order: user → project → local. F-M2 symlink guard each — refuse to follow a symlink at read time.
    if [ -z "$auto_memory_off_reason" ]; then
      for settings_path in "$HOME/.claude/settings.json" "./.claude/settings.json" "./.claude/settings.local.json"; do
        [ -L "$settings_path" ] && continue
        [ -f "$settings_path" ] || continue
        val=$(jq -r '.autoMemoryEnabled // empty' "$settings_path" 2>/dev/null)
        if [ "$val" = "false" ]; then
          auto_memory_off_reason="settings"
          auto_memory_off_path="$settings_path"
          break
        fi
      done
    fi
    ```

**If `auto_memory_off_reason` is non-empty (auto-memory is off):**

```bash
# Strip newlines, CR, NUL, ANSI CSI; truncate at 512 chars
sanitize_for_display() {
  printf '%s' "$1" | tr -d '\000\r\n' | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' | cut -c1-512
}
display_reason=$(sanitize_for_display "$auto_memory_off_path")
```

**If `--yes` was passed, skip the offer.** Print only the `warnings.auto_memory_disabled` warning (substituting `{reason}` with `$display_reason` — informational, useful in nap logs), set `auto_memory_now_on=false`, and continue with the normal flow. The user opted into non-interactive — do not block on a prompt.

**If `auto_memory_off_reason="env"`,** print `warnings.auto_memory_disabled` (substituting `{reason}` with `$display_reason`) AND print `warnings.auto_memory_unset_env_hint`. Do NOT offer to enable (the env var overrides settings — a write would be futile). Set `auto_memory_now_on=false` and continue.

**If `auto_memory_off_reason="settings"` (and `--yes` was NOT passed):**

1. Print `warnings.auto_memory_disabled` (substituting `{reason}` with `$display_reason`).
2. Use `AskUserQuestion` with question text `prompts.auto_memory_offer_enable_question` and exactly these three options:
   - `Yes, enable` → user_choice = `ENABLE`
   - `No, leave it off` → user_choice = `LEAVE`
   - `Let's chat about this` → user_choice = `CHAT`
3. Branching:
   - **`ENABLE`** → run the **Enable auto-memory subroutine** below, then continue.
   - **`LEAVE`** → continue with the normal flow. Auto-memory stays off; the empty-dir signal below is suppressed (the user knows the dir won't be auto-loaded — no need for a second warning).
   - **`CHAT`** → briefly explain in the user's locale (≤2 sentences): auto-memory is what loads the files in this directory into Claude Code at the start of each session. Without it, MemPenny still cleans, but Claude won't read what's left. Re-prompt with the same options.
   - **No answer (cancelled/dismissed)** → treat as `LEAVE`. (M3 — write nothing on cancel.)

Set a flag `auto_memory_now_on` based on the outcome:
- detection said on → `auto_memory_now_on=true`
- detection said off + user chose `ENABLE` and the subroutine succeeded → `auto_memory_now_on=true`
- otherwise → `auto_memory_now_on=false`

**Empty-dir signal (only when auto-memory is on):**

    ```bash
    md_count=$(find "$resolved" -maxdepth 1 -name "*.md" ! -name "MEMORY.md" -type f 2>/dev/null | wc -l)
    ```

If `auto_memory_now_on` is true AND `md_count` is 0 → print `warnings.memory_dir_empty_with_auto_on` (substituting `{path}` with `$resolved`). Continue regardless.

### Enable auto-memory subroutine

Run only when the user chose `ENABLE` above.

    ```bash
    SETTINGS="$HOME/.claude/settings.json"

    enable_failed=""

    # F-M2 symlink guard — refuse to write through a symlink
    if [ -L "$SETTINGS" ]; then
      enable_failed=1
      # Caller will print errors.settings_json_symlink with {path}=$SETTINGS
    fi
    ```

If `$enable_failed` is set, print `errors.settings_json_symlink` (substituting `{path}` with `$SETTINGS`) and skip the rest of the subroutine. Do NOT continue to the write. Set `auto_memory_now_on=false`.

Otherwise:

1. **Backup if file exists:**
       ```bash
       if [ -f "$SETTINGS" ]; then
         ts=$(date -u +%Y%m%d%H%M%S)
         bak="$SETTINGS.bak-$ts-$$"
         cp -a "$SETTINGS" "$bak"
         chmod 600 "$bak"
       fi
       ```
2. **Compute new content:**
       ```bash
       if [ -f "$SETTINGS" ] && jq empty "$SETTINGS" 2>/dev/null; then
         new_content=$(jq '. + {autoMemoryEnabled: true}' "$SETTINGS")
       else
         new_content='{"autoMemoryEnabled": true}'
       fi
       ```
3. **F-M2 escape closure: re-check just before Write, in case a symlink was planted between the initial check and now.**
       ```bash
       # F-M2 escape closure: re-check just before Write, in case a symlink was planted
       # between the initial check and now.
       if [ -L "$SETTINGS" ]; then
         rm -f "$SETTINGS"
       fi
       ```
4. **Write `$new_content`** to `$SETTINGS` using the Write tool.
5. **Tighten permissions:** `chmod 600 "$SETTINGS"`.
6. **Print `confirmations.auto_memory_enabled`** (substituting `{path}` with `$SETTINGS`).

**Layered-override check (after enabling):**

    ```bash
    layered_off=""
    for settings_path in "./.claude/settings.json" "./.claude/settings.local.json"; do
      [ -L "$settings_path" ] && continue
      [ -f "$settings_path" ] || continue
      val=$(jq -r '.autoMemoryEnabled // empty' "$settings_path" 2>/dev/null)
      if [ "$val" = "false" ]; then
        if [ -n "$layered_off" ]; then
          layered_off="$layered_off, $settings_path"
        else
          layered_off="$settings_path"
        fi
      fi
    done
    display_settings=$(sanitize_for_display "$SETTINGS")
    display_layered_off=$(sanitize_for_display "$layered_off")
    ```

If `$layered_off` is non-empty, print `confirmations.auto_memory_enable_layered_warning` (substituting `{paths}` with `$display_layered_off`). Substitute `{path}` with `$display_settings` wherever it appears in `confirmations.auto_memory_enabled`.

(End of auto-memory detection block — `--cancel` path skips everything above and resumes at Step 4.)

Hold the resolved value as `{MEMORY_DIR}` for the rest of the flow.

## Step 4 — Load config

**Config file location:** `~/.claude/mempenny.config.json`

**Schema (still v2 — `schedules` is an additive top-level section, introduced in v0.8.0):**

```json
{
  "version": 2,
  "memory_dirs": {
    "/abs/path/to/memory": "/abs/path/to/memory.backups"
  },
  "schedules": {
    "/abs/path/to/memory": {
      "frequency": "daily",
      "time": "03:00"
    }
  }
}
```

Per-memory-dir keying. `frequency` ∈ `{"daily", "weekly", "once"}`. `time` is `HH:MM` (24-hour, local). `/mempenny:clean` ignores `schedules` (it doesn't read this section); `/mempenny:nap` reads and writes both sections.

**Read logic** (mirrors `/mempenny:clean` Step 4):

1. **F-M2 + F2-M3 — symlink guard on the config file itself.** Run before Read:
   ```bash
   if [ -L ~/.claude/mempenny.config.json ]; then
     echo "MEMPENNY_CONFIG_INVALID=symlink"
   fi
   ```
   If the block printed `MEMPENNY_CONFIG_INVALID=symlink`, treat the on-disk config as empty for upsert purposes; do NOT Read the file.

2. Otherwise, Read `~/.claude/mempenny.config.json`. If the file does not exist, treat as empty.

3. Parse as JSON. If parsing fails, treat as empty (warn the user, but proceed).

4. **v1→v2 migration (mirrors `/mempenny:clean` Step 4 migration block):**
   Before running the v2 validation checks below, inspect the parsed JSON. If the top-level object contains `"version": 1` AND a string `backup_folder` (the legacy v0.4.x shape):
   - Apply the C1 regex + realpath + regex re-check to `backup_folder`: it must be a string, match `^/[A-Za-z0-9/_.\- ]{1,4096}$`, and `realpath "{backup_folder}"` must resolve to a path that still matches the same regex. If any gate fails, treat the v1 config as unusable: warn the user, skip the migration, and fall through to first-run setup with `{ "version": 2, "memory_dirs": {}, "schedules": {} }` — DO NOT clobber `memory_dirs`.
   - If all gates pass, build a v2 object in memory:
     ```json
     {
       "version": 2,
       "memory_dirs": { "<MEMORY_DIR>": "<realpath'd backup_folder from v1>" },
       "schedules": {}
     }
     ```
   - Persist immediately using the **Writing the config** block at the bottom of this file.
   - Print: `Migrated ~/.claude/mempenny.config.json from v1 to v2 (per-memory-dir config).`
   - Continue as if a valid v2 config was loaded all along.

5. **Validation (M1):**
   - Top-level must be a JSON object.
   - `version` must be the integer `2`.
   - `memory_dirs` (if present) must be an object whose every key and value matches `^/[A-Za-z0-9/_.\- ]{1,4096}$`. No `..` segment in any key or value. **C1 fix from v0.4.1 still applies — every entry, not just one.**
   - `schedules` (if present) must be an object. Every key must match the same C1 regex. Every value must be an object with:
     - `frequency`: one of `"daily"`, `"weekly"`, `"once"`.
     - `time`: must match `^([01]?[0-9]|2[0-3]):[0-5][0-9]$`.

   If `version` or `memory_dirs` validation fails, fall back to `{ "version": 2, "memory_dirs": {}, "schedules": {} }` and warn the user that `/mempenny:clean` should be re-run to set up `memory_dirs` properly. Don't repair `memory_dirs` here — that's `/clean`'s job.

   If `schedules` validation fails on a per-entry basis, treat that single entry as missing (drop it from the in-memory copy); leave other valid entries intact. If the whole `schedules` shape is wrong, treat the whole section as empty.

Hold the validated map as `{SCHEDULES}` (may be empty).

## Step 5 — `--list` short-circuit

If `--list` was passed:

1. If `{SCHEDULES}` is empty → print `nap.list_empty` and exit (success).
2. Otherwise, print `nap.list_header` followed by one line per entry (sorted by key):
   ```
   {nap.list_header}

   {nap.list_entry}    ← substitute {dir}, {frequency}, {time}
   ...
   ```
   Then exit.

## Step 6 — `--cancel` short-circuit

If `--cancel` was passed:

1. If `{SCHEDULES}["{MEMORY_DIR}"]` does not exist → print `errors.nap_no_schedule_for_dir` and exit.
2. Otherwise, build an updated config object: remove the `{MEMORY_DIR}` entry from `schedules`. Leave `memory_dirs` unchanged. Other `schedules` entries unchanged.
3. Run the **Writing the config** block at the bottom of this file.
4. Print `nap.cancelled_confirmation`. Exit.

## Step 7 — Resolve backup folder

(This step and the rest of the flow only run if neither `--list` nor `--cancel` was passed.)

Look up `memory_dirs["{MEMORY_DIR}"]` in the loaded config:

- **Found** → that path is the proposed default for the prompt.
- **Not found** → propose `<MEMORY_DIR>.backups` (the same default `/mempenny:clean` uses on first run).

Use `AskUserQuestion` with question text `nap.prompt_backup_folder` and exactly these three options:

- `nap.option_use_default_backup` (substitute `{path}` with the proposed default) — Recommended → user_choice = `DEFAULT`
- `nap.option_custom_path` → user_choice = `CUSTOM` (free-text follow-up: ask for an absolute path)
- `nap.option_chat` → user_choice = `CHAT`

Match by exact label string. Branching:

- `DEFAULT` → use the proposed default path.
- `CUSTOM` → the free-text response is the candidate path.
- `CHAT` → drop into discussion mode. Briefly explain (in the user's locale, at most 2 sentences) what the backup folder is for: it's where `/mempenny:clean` writes a timestamped snapshot before any modification, so any nap-triggered cleanup is reversible via `/mempenny:restore`. Answer follow-up questions. Then re-invoke this same `AskUserQuestion`. **Do not write anything to disk during chat mode.**
- No answer (cancelled/dismissed) → print `nap.aborted` and exit. Write nothing. (M3)

**Validate the candidate path (C1 + H4):**

1. **Regex:** `^/[A-Za-z0-9/_.\- ]{1,4096}$`.
2. **Realpath:** `realpath "<candidate>"`. Reject if not resolvable. Use the resolved value going forward.
3. **Overlap (H4):** reject if `realpath({candidate})` has `realpath({MEMORY_DIR})` as a prefix, OR vice versa.
4. **Depth:** reject `/`, anything with fewer than 2 path components, `realpath $HOME` (if `$HOME` is set non-empty), or `/root/*` (if `EUID == 0`).
5. **Writability:** `mkdir -p "{candidate}" && touch "{candidate}/.mempenny-write-test" && rm "{candidate}/.mempenny-write-test"`. Hard-fail on any of mkdir/touch/rm error.
6. **Parent exists:** `[ -d "$(dirname "$resolved")" ]`.

**Hard block if backup folder is under `/tmp` or `/var/tmp`:**

```bash
case "$realpath_backup" in
  /tmp/*|/tmp|/var/tmp/*|/var/tmp)
    print errors.backup_folder_in_tmp (substituting {path} with $realpath_backup)
    re-prompt (existing 3-retry cap applies)
    ;;
esac
```

If any check fails, show `errors.backup_folder_invalid` with the offending path and re-prompt (3-retry cap, then abort with `nap.aborted`).

If all checks pass, hold the realpath value as `{BACKUP_ROOT}` and print `nap.access_ok`. Queue an upsert into `memory_dirs["{MEMORY_DIR}"] = {BACKUP_ROOT}` for Step 10 — so this prompt also seeds `/clean`'s config if it wasn't there before.

## Step 8 — Resolve frequency

If a schedule already exists for `{MEMORY_DIR}` (i.e., `{SCHEDULES}["{MEMORY_DIR}"]` is non-empty), use its `frequency` value as the recommended option below; otherwise recommend `Daily`.

Use `AskUserQuestion` with question text `nap.prompt_frequency` and exactly these four options (in this order):

- `nap.option_freq_daily` (Recommended unless overridden above) → user_choice = `DAILY`
- `nap.option_freq_weekly` → user_choice = `WEEKLY`
- `nap.option_freq_once` → user_choice = `ONCE`
- `nap.option_chat` → user_choice = `CHAT`

Branching:

- `DAILY` / `WEEKLY` / `ONCE` → set `{FREQUENCY}` accordingly (lowercase string).
- `CHAT` → briefly explain (at most 2 sentences): daily fires once per calendar day after the scheduled time; weekly fires if at least 7 days have passed since the last fire; once fires exactly one time and stays dormant in the config until you re-schedule or `--cancel`. Answer follow-ups. Re-prompt.
- No answer → print `nap.aborted` and exit. (M3)

## Step 9 — Resolve time

If a schedule already exists for `{MEMORY_DIR}`, the proposed default is its existing `time`; otherwise `03:00`.

Use `AskUserQuestion` with question text `nap.prompt_time` and exactly these three options:

- `nap.option_use_default_time` (substitute `{time}` with the proposed default) — Recommended → user_choice = `DEFAULT`
- `nap.option_custom_time` → user_choice = `CUSTOM` (free-text follow-up: ask for `HH:MM`)
- `nap.option_chat` → user_choice = `CHAT`

Branching:

- `DEFAULT` → `{TIME}` = the proposed default.
- `CUSTOM` → validate the response against `^([01]?[0-9]|2[0-3]):[0-5][0-9]$`. Normalize to `HH:MM` (zero-pad single-digit hour). If validation fails, show `errors.nap_time_invalid` with the offending value and re-prompt (3-retry cap, then abort).
- `CHAT` → briefly explain (at most 2 sentences): the time is the earliest moment nap is allowed to fire in your local timezone; the actual cleanup runs the next time you open Claude Code in this project after that time. Answer follow-ups. Re-prompt.
- No answer → print `nap.aborted` and exit. (M3)

## Step 10 — Write the schedule

Build the updated config object:

1. Start from the in-memory config object loaded in Step 4 (or `{ "version": 2, "memory_dirs": {}, "schedules": {} }` if it was empty/invalid).
2. Upsert `memory_dirs["{MEMORY_DIR}"] = {BACKUP_ROOT}` from Step 7. Other entries in `memory_dirs` unchanged.
3. Upsert `schedules["{MEMORY_DIR}"] = { "frequency": "{FREQUENCY}", "time": "{TIME}" }` from Steps 8 and 9. Other entries in `schedules` unchanged.
4. Run the **Writing the config** block at the bottom of this file.

Hold a flag `{WAS_PRE_EXISTING}` indicating whether `schedules["{MEMORY_DIR}"]` was non-empty before this run — this controls the wording in Step 11.

## Step 11 — Print confirmation

If `{WAS_PRE_EXISTING}` is true → use `nap.updated_confirmation`.
Otherwise → use `nap.scheduled_confirmation`.

```
{nap.scheduled_confirmation OR nap.updated_confirmation}    ← substitute {frequency} with the chosen option_freq_* value (e.g., "Daily"), and {time} with the resolved HH:MM
{nap.remove_hint}
```

Exit.

---

## Writing the config (upsert — preserves all other entries)

1. Compute the absolute target path: `~/.claude/mempenny.config.json`.
2. Run the following bash block unconditionally before the Write call:
   ```bash
   # F-M2 escape closure: if the config path is a symlink (planted between
   # read-time check and write), remove it before Write so we don't overwrite
   # the symlink target.
   if [ -L ~/.claude/mempenny.config.json ]; then
     rm -f ~/.claude/mempenny.config.json
   fi
   ```
3. Write the full in-memory object using the Write tool. Every other key in `memory_dirs` and `schedules` must survive the write unchanged — only the `{MEMORY_DIR}` keys are added, replaced, or (for `--cancel`) removed.
4. After writing, run `chmod 600 ~/.claude/mempenny.config.json` via Bash. **(L1)**

## Notes for the implementer

- **Do not modify `/mempenny:clean`** while implementing nap. The cleanup that nap triggers is the existing `/clean` flow with all its existing safety. Nap only writes config; the actual file mutations happen via the `SessionStart` hook → model invokes `/mempenny:clean` → `/clean`'s gate asks the user → backup-then-apply runs.
- **Hook script lives at `${CLAUDE_PLUGIN_ROOT}/hooks/nap-check.sh`.** Plugin-shipped, auto-active for every user who installs MemPenny. Never modify the user's `~/.claude/settings.json`.
- **State file lives at `${CLAUDE_PLUGIN_DATA}/nap-<sha1-12>.last`** where `<sha1-12>` is the first 12 hex chars of `sha1sum` of the realpath'd memory dir. This namespaces the state per-memory-dir so multiple projects can have independent nap schedules.
- **Auth-agnostic:** the hook runs in whatever interactive Claude Code session the user has open; it does not care whether the user authenticated via OAuth or API key. Nap works for everyone with Claude Code.
