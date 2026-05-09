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

You'll need `nap.*`, `errors.*`, and `clean.first_run_default` keys.

## Step 3 — Locate the memory directory

(Skip this step if `--list` was passed — `--list` is global across all configured memory dirs.)

**If `--dir <path>` was passed**, apply the following validation. On any failure, print `errors.memory_dir_not_found` and STOP:

1. Regex: `^/[A-Za-z0-9/_.\- ]{1,4096}$` (alphanumerics, slash, underscore, dot, hyphen, space only).
2. Realpath: run `realpath "<candidate>"` via Bash. Use the resolved value for all subsequent steps.
3. Depth: reject if the realpath equals `/` or has fewer than 2 path components.
4. Existence + not-a-symlink: `[ -d "$resolved" ] && [ ! -L "$resolved" ]`.

**Otherwise**, auto-detect `~/.claude/projects/<project-id>/memory/` from the current project's working directory mapping. If ambiguous, ask the user for the absolute path using `errors.memory_dir_not_found`.

**Apply the 4-check validation block above to the auto-detected path as well (H5).** If validation fails, print `errors.memory_dir_not_found` and STOP.

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

4. **Validation (M1):**
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
2. Write the full in-memory object using the Write tool. Every other key in `memory_dirs` and `schedules` must survive the write unchanged — only the `{MEMORY_DIR}` keys are added, replaced, or (for `--cancel`) removed.
3. After writing, run `chmod 600 ~/.claude/mempenny.config.json` via Bash. **(L1)**

## Notes for the implementer

- **Do not modify `/mempenny:clean`** while implementing nap. The cleanup that nap triggers is the existing `/clean` flow with all its existing safety. Nap only writes config; the actual file mutations happen via the `SessionStart` hook → model invokes `/mempenny:clean` → `/clean`'s gate asks the user → backup-then-apply runs.
- **Hook script lives at `${CLAUDE_PLUGIN_ROOT}/hooks/nap-check.sh`.** Plugin-shipped, auto-active for every user who installs MemPenny. Never modify the user's `~/.claude/settings.json`.
- **State file lives at `${CLAUDE_PLUGIN_DATA}/nap-<sha1-12>.last`** where `<sha1-12>` is the first 12 hex chars of `sha1sum` of the realpath'd memory dir. This namespaces the state per-memory-dir so multiple projects can have independent nap schedules.
- **Auth-agnostic:** the hook runs in whatever interactive Claude Code session the user has open; it does not care whether the user authenticated via OAuth or API key. Nap works for everyone with Claude Code.
