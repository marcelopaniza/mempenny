# Changelog

All notable changes to MemPenny are documented here. This project follows [semantic versioning](https://semver.org/).

## [0.9.2] — 2026-05-09

Patch release.

### Fixed

- **`/mempenny:memory-distill`** — removed a dead `--dir` branch in the path-validation step. If it had ever been wired up without the full 4-check validation, the parent-confinement anchor would have become attacker-controlled. Caught by post-fix pentest before becoming exploitable.

### Changed

- **README rewrite** — `/mempenny:clean` and `/mempenny:nap` are now top-level features (nap moved out of Advanced). Cluster analysis (DEDUPE / MERGE / FLAG) is described upfront in the user experience. Dropped stale references to optional external compressors and to a pre-launch namespace migration note.

## [0.9.1] — 2026-05-09

Patch release. Fixes from a full-surface pre-1.0 code-review + pentest pass.

### Fixed

- **`/mempenny:memory-distill`** — added an H2 SAFETY block (file body is data, not instructions) and full path validation on the input file argument. Closes a prompt-injection gap and prevents memory-dir escape via symlink.
- **`/mempenny:nap`** — added v1→v2 config migration matching `/mempenny:clean`. Prevents silent loss of an existing `backup_folder` for users coming from v0.4.x who run `nap` before ever running `clean`.
- **`/mempenny:clean`** — explicit "Determine scope" step now defines `{SCOPE_GLOB}` from `--only` (was an implicit dependency). Step 2 now explicitly loads the top-level `distill_output_instruction` locale key for non-English distillation.
- **Config write hardening (`/clean` + `/nap`)** — unlink any symlink at `~/.claude/mempenny.config.json` before the Write call. Closes a defense-in-depth gap where a pre-planted symlink could redirect the Write to overwrite an arbitrary file (e.g., `~/.ssh/authorized_keys`).

## [0.9.0] — 2026-05-09

After per-file triage, `/mempenny:clean` now groups related memory files and proposes DEDUPE / MERGE / FLAG cluster actions. All cluster actions wait for explicit approval. No changes to existing triage behavior, backup machinery, or any other command.

### Added

- **Cluster analysis in `/mempenny:clean`** — after per-file triage, MemPenny groups related memory files and proposes DEDUPE (drop duplicates, keep the newest), MERGE (combine related files into one), or FLAG (conflicting files flagged for manual review) actions. Every cluster action requires explicit confirmation before anything is modified.
- New locale keys for the cluster summary section (`en`, `es`, `pt-BR` parity preserved).

### Notes

- Cluster proposals only appear when MemPenny is highly confident in the grouping. Lower-confidence groupings emit a brief informational note in the summary; no action is proposed for them.
- Backup-first behavior is unchanged: every action goes through the same backup machinery, restoreable via `/mempenny:restore`.
- No changes to `/mempenny:restore`, `/mempenny:memory-triage`, `/mempenny:memory-apply`, `/mempenny:memory-distill`, or `/mempenny:nap`. No changes to backup format or config schema.

## [0.8.0] — 2026-05-09

Add `/mempenny:nap` — schedule `/mempenny:clean` to run on a recurring basis. Pure scheduling: no new triage logic, no consolidation, no auto-apply path. Existing commands unchanged.

### Added

- **`/mempenny:nap`** — three-question configure flow: backup folder → frequency (daily / weekly / once) → time (default `03:00` local). Persists into a new additive `schedules` top-level section in `~/.claude/mempenny.config.json`. `version` stays `2`. Every prompt offers a "Let's chat about this" option so the user can ask questions instead of being forced to pick.
- **`/mempenny:nap --list`** — print all configured schedules.
- **`/mempenny:nap --cancel`** — remove the schedule entry for the current memory dir.
- **Plugin-shipped `SessionStart` hook** at `hooks/hooks.json` + `hooks/nap-check.sh`. Auto-active for every user who installs MemPenny — never touches the user's `~/.claude/settings.json`. Reads the schedule from config, checks a per-memory-dir state file at `${CLAUDE_PLUGIN_DATA}/nap-<sha1-12>.last`, emits a `hookSpecificOutput.additionalContext` payload only when nap is due (after the scheduled time today AND not already fired according to frequency rules). Defensive bash — every potentially-failing step ends with `|| exit 0` so a broken hook can never block session start.
- **Locale strings** for nap added to `en`, `es`, `pt-BR` (75 keys → 97 keys, parity preserved).
- **README section** "Scheduling with `/mempenny:nap`".

### Notes

- **Auth-agnostic.** Nap runs inside whatever interactive Claude Code session the user opens, regardless of OAuth vs API key. The hook never invokes the `claude` CLI itself.
- **No `--yes` flag on `/clean`.** Nap's mechanism is the model invoking `mempenny:clean` via the `Skill` tool inside the user's REPL session — `/clean`'s existing "Yes / No / Show full" gate is preserved because the user is in the REPL when nap fires.
- **Uses Claude credits per fire** — same as a manual `/clean`. Disclosed at scheduling time and in the README.
- **Linux + macOS** for v0.8.0. Windows support deferred.
- **Frequency / time override flags** (`--time`, `--frequency`) deferred to v0.9.0 to keep the v0.8.0 surface minimal.
- **Known limitation:** if you open two Claude Code sessions for the same project at the same moment, both `SessionStart` hook runs can pass the "haven't fired today" check before either writes the state file, resulting in two `additionalContext` payloads and (potentially) two `/clean` invocations. The double-run is harmless — `/clean` is idempotent — but it's a correctness wart. Cross-platform `flock` would fix it; deferred until a real user reports actual double-fires.
- No changes to `/clean`, `/restore`, `/memory-triage`, `/memory-apply`, `/memory-distill`. No changes to backup format. No changes to privacy guarantees beyond a small note about the new local state file in `$CLAUDE_PLUGIN_DATA`.

## [0.7.0] — 2026-04-26

Revert the v0.4.0 namespace abbreviation. Slash commands invoke as `/mempenny:…` again. The `mp` short prefix turned out to be unmemorable in practice — typing `mem<tab>` in the slash menu produced no completion, which negated the point of the abbreviation.

### Changed (breaking)

- **Plugin name `mp` → `mempenny`** in `.claude-plugin/plugin.json` and the marketplace plugin entry. Reinstall the plugin to pick up the new namespace.
- **All slash commands re-namespaced from `/mp:…` to `/mempenny:…`.** Affected: `/mempenny:clean`, `/mempenny:restore`, `/mempenny:memory-triage`, `/mempenny:memory-apply`, `/mempenny:memory-distill`. Locale strings in `en`, `es`, `pt-BR` updated to match.

### Notes

- No behavioral, config, or backup format change. `~/.claude/mempenny.config.json` (the file name was always `mempenny`) and existing backup directories are untouched.
- Migration: `/plugin uninstall mp@mempenny` then `/plugin install mempenny@mempenny`, or `/plugin update`.
- README upgrade notice flipped to point users coming from 0.4.x–0.6.x at the new namespace.

## [0.6.0] — 2026-04-19

Remove the optional downstream compressor hook from MemPenny's execution path. MemPenny now stays entirely within the delete / archive / distill / keep strategy hierarchy; any prose-level compression the user wants to do is on them to invoke separately.

### Removed (breaking)

- **`/mp:memory-compress` command removed.** The command was a thin router to an optional external compressor. If you were using it, invoke your compressor of choice directly instead.
- **`/mp:clean` no longer offers a compressor handoff.** The Step 8 apply prompt is back to three options: `Yes, apply` / `No, cancel` / `Show full table`. Step 11 (previously the 4-branch compressor-handoff dispatcher) is gone.
- **`/mp:memory-apply` no longer prints a "next step: run compress" suggestion.** The apply finishes, prints its summary, and exits.

### Removed (locale)

- `apply.next_step_header`, `apply.next_step_suggestion`
- `apply.terse_md_handoff_note`, `apply.terse_md_not_installed_hint`, `apply.terse_md_path_has_space_note`, `apply.terse_md_skipped_by_user`
- `errors.terse_md_not_installed_prose`, `errors.terse_md_path_has_space`

All three locales (`en`, `es`, `pt-BR`) now carry the same 75 keys.

### Notes

- No config schema change (still v2, per-memory-dir).
- No backup / restore format change.
- The README still mentions optional external compressors as something a user can choose to run separately — MemPenny itself no longer references them.
- Migration: if you relied on `/mp:memory-compress`, install and invoke your compressor of choice directly after `/mp:clean` finishes.

## [0.5.2] — 2026-04-19

Fold the terse-md handoff into the existing `/mp:clean` apply prompt so the user makes both decisions (apply the triage; run terse-md after) in a single interaction. Previously, terse-md was auto-invoked at Step 11 when installed, which was surprising for users who only wanted the triage step.

### Changed

- **`/mp:clean` Step 8 now offers up to four options instead of three.** When `terse-md:run` is installed AND `{MEMORY_DIR}` contains no space, the prompt presents:
  - `Yes, apply + run terse-md after` (Recommended)
  - `Yes, apply only`
  - `No, cancel`
  - `Show full table`

  When terse-md is missing or the path has a space, the prompt falls back to the pre-v0.5.2 three-option list (`Yes, apply` / `No, cancel` / `Show full table`) — those users never see an option they can't act on.

- **Step 11 now branches on the Step 8 choice.** Four exhaustive branches: (A) user asked for terse-md and we invoke it, (B) user declined terse-md → short "skipping, run later" note, (C) terse-md was never offered because it's not installed → not-installed hint + install block, (D) terse-md was installed but path had a space → space note. The install block is still hardcoded in `clean.md` (never from the locale), preserving the v0.5.1 H2 fix.

- **Locale:** new key `apply.terse_md_skipped_by_user` added to `en`, `es`, `pt-BR`. No existing keys renamed or removed.

### Notes

- Terse-md's own first-run "Ready? Continue" gate still fires after our handoff. That's a gate inside terse-md's pipeline (before it processes files) and is unchanged — we do not bypass it.
- No breaking changes. Config schema (still v2), backup format, and rollback semantics are identical to v0.5.1.

## [0.5.1] — 2026-04-19

Swap the optional downstream compressor from caveman to [terse-md](https://github.com/marcelopaniza/terse-md). MemPenny's own behavior (triage: delete / archive / distill) is unchanged. Users who had caveman installed and relied on `/mp:memory-compress` should install terse-md to keep a compression step in the pipeline; users who never installed caveman see no behavioral difference, just a different install hint if they invoke compress.

### Changed

- **`/mp:memory-compress` now routes to `/terse-md:run` instead of `caveman:compress`.** Detection checks for `terse-md:run` in the skills list. If installed, MemPenny invokes it with `--all <memory-dir>` (plus pass-through `--dry-run` / `--include-all` if provided). If not installed, MemPenny prints the terse-md install commands and stops without modifying anything. Note: terse-md has a different compression model than caveman — it writes `.approved.yaml` siblings on explicit per-file approval rather than overwriting sources with `.original.md` backups. MemPenny does not create a separate backup for this command; terse-md never overwrites source files.

- **`/mp:clean` auto-chains to terse-md at the end of a successful clean, if installed.** A new Step 11 detects `terse-md:run`; if present, MemPenny hands off with a single `/terse-md:run --all <memory-dir>` invocation. If terse-md is not installed, MemPenny prints an honest one-paragraph note saying compression is optional and pointing at the terse-md install command. No nagging, no retries — skipping the step is fine.

- **Locale key rename:** `errors.caveman_not_installed_prose` → `errors.terse_md_not_installed_prose`. Two new keys added: `apply.terse_md_handoff_note` and `apply.terse_md_not_installed_hint`. The `compress.*` locale section (caveman-specific summary labels) was removed — MemPenny no longer prints its own compression report; terse-md prints its own.

- **README restructured into Default and Advanced sections.** Default: one command (`/mp:clean`) with end-to-end description. Advanced: manual phase commands, flags, config file shape, rollback recipes, localization, strategy hierarchy.

### Removed

- Caveman references throughout the docs, commands, and locales. MemPenny and caveman remain cleanly independent at the plugin level — there's just no built-in pointer anymore.

### Notes for existing users

- No config migration needed — the `~/.claude/mempenny.config.json` schema did not change in this release.
- If you had caveman installed and were using `/mp:memory-compress`, the command still runs but will tell you terse-md isn't installed. Install terse-md to continue having a compression step.
- If you used neither, nothing changes in practice.

## [0.5.0] — 2026-04-18

Per-memory-dir backup config. Fixes a usability bug where `/mp:clean` prompted for a backup folder only on the very first run globally, then silently reused that one folder for every other project on the same machine — with no way to tell which backup came from which project.

### Changed

- **Config schema v2 (breaking, auto-migrated).** `~/.claude/mempenny.config.json` was a single `backup_folder` string shared across all memory dirs (v1). v0.5 replaces it with a `memory_dirs` object that maps each memory directory to its own backup folder:

  ```json
  {
    "version": 2,
    "memory_dirs": {
      "/abs/path/to/project-a/memory": "/abs/path/to/project-a/memory.backups",
      "/abs/path/to/project-b/memory": "/abs/path/to/project-b/memory.backups"
    }
  }
  ```

  First `/mp:clean` run in each memory directory prompts for a backup folder and adds an entry. Subsequent runs against the same directory are one command. `--reconfigure` now re-prompts **only for the current memory directory**, leaving other entries untouched.

- **`/mp:clean` auto-migrates v1 configs to v2 on first run.** The v0.4.x `backup_folder` value is preserved for the current memory directory only. Any other project you run `/mp:clean` in afterward gets its own fresh prompt. A one-liner is printed explaining the migration. `/mp:restore` and `/mp:memory-apply` read v1 configs (preserving the v0.4 "single global folder" behavior) without writing — only `/mp:clean` migrates.

- **`/mp:restore` scopes backup listing to the current memory dir.** Previously all backups from all projects would have commingled under one folder with colliding names; the v2 layout naturally confines the listing to the current project. If you run `/mp:restore` against a memory dir with no v2 entry (and no v1 config), you now see `restore.no_config_for_dir` with the directory path, and are directed to run `/mp:clean` first.

- **`/mp:memory-apply` looks up the per-dir entry; falls back to sibling path when none exists.** A user who hasn't run `/mp:clean` yet still gets the legacy sibling-directory backup — unchanged low-friction path. The only difference is that the config entry, if present, is now keyed by memory directory.

### Added

- `restore.no_config_for_dir` locale key (en / es / pt-BR) surfaced when `/mp:restore` is run against a memory dir with no backup-folder entry yet.
- README section "Config file" documenting the v2 shape, the first-run-per-directory flow, and the v1→v2 migration.

### Migration

Users upgrading from v0.4.x: **no manual action required.** The first `/mp:clean` you run under v0.5 migrates `~/.claude/mempenny.config.json` in place and preserves your old backup folder for the memory dir you ran it from. Any other project on the same machine will prompt on its first `/mp:clean` run. Existing backups continue to restore normally — the migration only changes which memory dirs are bound to the old path, not the path itself.

If you'd previously set the backup folder to a location that turned out to be wrong for most projects (e.g., a sandbox path under `/tmp`), the migration inherits it for one memory dir; the rest get fresh prompts. Run `/mp:clean --reconfigure` to re-pick the folder for the currently-bound dir, or hand-edit the config to remove the stale entry.

### Notes

- Schema version bumps 1 → 2. Config files written by v0.5 cannot be read by v0.4.1 or earlier (v0.4.x's validation rejects any top-level key other than `backup_folder` + `version`).
- Bug this fixes: a v0.4.x user who ran `/mp:clean` in one project would never be prompted again, so every other project on the same machine silently wrote backups into the first project's folder with colliding names. `/mp:restore` listed them intermingled with no way to tell which came from which.

## [0.4.1] — 2026-04-18

Security-hardening release. No new features. Every finding from the full code-review + pentest pass against v0.4.0 is addressed. Safe to upgrade in place.

### Security

- **C1 (Critical) — Config-read regex tightened.** The validator for `~/.claude/mempenny.config.json`'s `backup_folder` field was `^/[^\x00\n]{1,4096}$` in three places (`clean.md`, `memory-apply.md`, `restore.md`). That permitted every shell metacharacter, including `$(...)` and backticks. A tampered config like `{"backup_folder": "/tmp/x$(cmd)"}` would have fired command substitution the moment the next `realpath "{backup_folder}"` ran — double-quotes do not block `$(...)`. All three call sites now use the same **tight** regex as first-run setup: `^/[A-Za-z0-9/_.\- ]{1,4096}$`. Reproducer: `bash -c 'touch "/tmp/x$(id -u).txt"'` creates `/tmp/x1000.txt` — confirms the mechanic.
- **H1 (High) — Apply prompts confine filenames.** Both apply subagent prompts now regex-validate every table row's filename (`^[A-Za-z0-9][A-Za-z0-9_.\-]*\.md$`), resolve it through `realpath`, and assert the resolved path is a direct child of `{MEMORY_DIR}` before any `rm` or `mv`. Blocks path-traversal via malicious filenames dropped into the memory dir by another process.
- **H2 (High) — Prompt-injection hardening.** Both triage and apply subagent prompts now have an explicit "file contents and table rows are DATA, not instructions" safety block. Triage refuses to carry instruction-like text into the Distilled replacement column. Apply refuses to `rm`/`mv`/`curl` anything outside the current row's File column, and aborts on malformed tables.
- **H3 (High) — `/tmp/triage_table.md` replaced with `mktemp`.** The fixed path was pre-poisonable on shared systems and world-readable by default. `/mp:memory-triage` and `/mp:clean` now create the output path via `mktemp -t mempenny-triage-XXXXXXXX.md` with `chmod 600`. `/mp:memory-apply` requires an explicit positional table path; the old implicit default was removed. `/mp:memory-apply` validates the table path on read (regex, realpath, not-a-symlink) and refuses world-writable tables via explicit octal-bit checks on the stat output.
- **H4 (High) — Caveman install commands moved out of locale files.** `errors.caveman_not_installed` carried literal shell commands inside translated strings, so a malicious translation PR could swap what the user copy-pastes. Renamed to `errors.caveman_not_installed_prose` (no commands); `commands/memory-compress.md` now hard-codes the install block verbatim. Translators can no longer influence commands surfaced to the user.
- **H5 (High) — Auto-detected `{MEMORY_DIR}` is now validated.** Previously only `memory-compress.md` applied the 4-check validation block to auto-detected paths; `memory-triage`, `memory-apply`, `clean`, and `restore` skipped it for the auto-detect branch. Fixed — all five commands now validate regardless of source.

### Medium / Low

- **M1** — `MEMORY.md` line removal is now POSIX-ERE–driven with regex-escaped filenames instead of substring-matching "looks like a link" instructions.
- **M2** — Apply subagents now run invariant checks before returning: removed/archived counts match validated-table counts, MEMORY.md line delta ≤ removed+archived, no files outside the table changed (sha256/mtime vs. backup).
- **M3** — Cross-filesystem check on `{MEMORY_DIR}/archive/`. If on a different FS (user-bind-mounted), `mv` is replaced with `cp -a && rm -f` per row.
- **M4** — Backups now carry a `MANIFEST.sha256`. `/mp:restore` verifies it before any `cp -a`. Old v0.4.0 backups without a manifest restore silently (compat).
- **M5** — Bash counter advisory hardened: `count=$((count+1))` preferred; fallback guidance for any legacy `((count++))` is to neutralize with `|| true`.
- **L1** — `PRIVACY.md` now includes an explicit prompt-injection threat-model paragraph. The v0.4.0 wording "no code ... could exfiltrate" is narrowly true but needed context.
- **L2** — `--only <glob>` values validated against `^[A-Za-z0-9_.\-*?\[\]{},/ ]{1,256}$` before reaching `find`.
- **L3** — Backup creation now does `chmod -R go=` in addition to the top-dir `chmod 700`.

### Changed

- **`/mp:memory-apply` no longer defaults to `/tmp/triage_table.md`.** Pass the path printed by `/mp:memory-triage` as the first positional argument. This is a breaking change for anyone scripting `memory-apply` directly; `/mp:clean` users are unaffected.
- Stale `/memory-triage`, `/memory-apply`, `/memory-distill` references in command files and locale strings are all now `/mp:…` — completes the 0.4.0 rename that the CHANGELOG had listed as done.
- Symmetric backup/memory-dir overlap check in `memory-apply.md` (was one-way) matches `clean.md`'s bidirectional check.
- Localized the backup-pruning reminder and the post-restore retention reminder (new keys: `clean.backup_pruning_hint`, `restore.safety_retention_hint` in all three locales).

### Notes

- No data migration needed. Existing backups continue to restore fine.
- The one breaking change (`/mp:memory-apply` requires an explicit table path) is limited to power users. The everyday `/mp:clean` flow is unchanged.
- Threat model covered: adversarial config file (incl. symlink replacement), adversarial memory filenames (incl. symlinks), adversarial `{MEMORY_DIR}/archive/` (symlink OOB-write primitive), adversarial memory-file contents, shared `/tmp`, malicious translation PRs, and backup-dir tampering (modify + ADD detection via `MANIFEST.sha256`). The Claude Code runtime's own prompt-injection surface is called out but outside MemPenny's scope to fix.
- **Platform:** the bash snippets use GNU coreutils idioms (`stat -c %d`, `sha256sum`, `find -print0 | sort -z | xargs -0`, `realpath` returning successfully on non-existent paths). On BSD/macOS some of these behave differently. MemPenny is Linux-first; macOS/BSD support is best-effort until explicitly tested.
- **Cross-filesystem ARCHIVE:** `mv` into `{MEMORY_DIR}/archive/` is atomic only when source and destination are on the same filesystem. If a user has bind-mounted `archive/` to a different FS, MemPenny detects this via `stat -c %d` and falls back to `cp -a <src> <dst> && rm -f "$src" || { rm -f "$dst"; false; }`. The fallback isn't perfectly atomic — cp can succeed and rm can fail (permissions/FS full), leaving the file duplicated; the `|| rm -f "$dst"` rollback clause keeps the source authoritative in that edge case.

## [0.4.0] — 2026-04-17

### Breaking
- **Plugin renamed from `mempenny` to `mp`.** All slash commands now invoke as `/mp:…` instead of `/mempenny:…`. Existing installs need to reinstall; there is no alias layer. The marketplace entry remains `marcelopaniza/mempenny` for discovery — only the invocation prefix changed.

### Added
- **`/mp:clean [--dir <path>] [--only <glob>] [--lang <code>] [--reconfigure]`** — one-shot memory cleanup. Triage + apply in a single pass with a single confirm gate. First run prompts for a backup folder (default: `<memory-dir>.backups/`) and saves the choice to `~/.claude/mempenny.config.json`; subsequent runs reuse it automatically. Backups go to `<backup-folder>/memory.backup-YYYYMMDDHHMMSS/` with a per-second timestamp so you can keep multiple backups side by side.
- **`/mp:restore [<backup-name>|latest] [--dir <path>] [--lang <code>]`** — restore a backup created by `/mp:clean`. Lists available backups, prompts you to pick one (or pass `latest`), takes a safety snapshot of the current memory dir at `<memory-dir>.pre-restore-YYYYMMDDHHMMSS/` before overwriting, then restores. The safety snapshot means the restore itself is reversible.
- **`clean.*` and `restore.*` sections in all three locale files** (`en`, `pt-BR`, `es`) covering first-run setup, triage summary labels, confirm prompts, and safety-snapshot notes.
- **New error keys** `errors.backup_folder_invalid` and `errors.backup_not_found` for config path validation and restore lookup failures.

### Changed
- All `/mempenny:…` cross-references inside existing command files and the `apply.next_step_suggestion` locale string updated to `/mp:…`.
- `/mp:memory-apply` now reads `~/.claude/mempenny.config.json` and writes backups to `{BACKUP_ROOT}/memory.backup-YYYYMMDDHHMMSS-PID/` when present, so `/mp:restore` can roll them back. Falls back to `{MEMORY_DIR}.backup-YYYYMMDDHHMMSS-PID/` when no config exists.
- Fixed a same-day overwrite bug: `/mp:memory-apply` previously used a date-only timestamp that silently overwrote a prior same-day backup. Now uses UTC second-resolution + PID suffix.
- Existing commands (`/mp:memory-triage`, `/mp:memory-apply`, `/mp:memory-distill`, `/mp:memory-compress`) are unchanged in behavior except for the invocation prefix and the backup-path unification above.

### Security
- Regex-gated `--dir` path validation (shell-injection guard) added to all five commands that accept `--dir`: `clean`, `restore`, `memory-triage`, `memory-apply`, `memory-compress`.
- Locale path traversal guard (H2): `--lang` validated against `^[a-zA-Z]{2,3}(-[A-Za-z0-9]{2,8})?$` in all six commands before constructing the locale file path.
- Realpath canonicalization and symlink rejection on all user-supplied directory paths.
- `set -euo pipefail` added to all destructive bash blocks in memory-apply's apply prompt.
- `mkdir -m 700` on backup directories; `chmod 600` on config file (both inherited from clean.md hardening).
- Symlink-safe restore: Step 6 + Step 9 in restore.md reject symlinks before any `cp -a`.

### Notes
- Old backups created by `/mp:memory-apply` (date-only suffix, sibling path) are untouched and remain rollback-able by hand.
- No data migration needed.

## [0.3.0] — 2026-04-11

### Added
- **`/mempenny:memory-compress [--dir <path>] [--only <glob>] [--lang <code>]`** — new slash command that invokes `caveman:compress` on every surviving memory file in a directory. Shrinks prose while preserving code, commands, URLs, paths, frontmatter, and version numbers exactly. Per-file backups are handled by caveman natively (creates `FILE.original.md` alongside each compressed file).
- **Graceful caveman detection.** `/mempenny:memory-compress` checks its available skills list for `caveman:compress` before touching any files. If caveman isn't installed, it prints the install instructions and exits without modifying anything — MemPenny still works fully standalone. The `caveman_not_installed` error message is in all three shipped locales.
- **Trailing "next step" suggestion** on `/mempenny:memory-apply` output — after a successful apply, the command now recommends running `/mempenny:memory-compress --dir <same-dir>` as the logical next step. The suggestion is localized.
- **`compress` section in all three locale files** (`en`, `pt-BR`, `es`) with labels for the summary block, rollback note, and nothing-to-compress edge case.
- **README "After MemPenny: compress with caveman" section** — concrete end-to-end example (`triage → apply → compress`), the graceful-fallback story, and typical savings numbers when stacking both tools.

### Changed
- README quick-start now shows the full three-step flow (`triage → apply → compress`) alongside the minimum dry-run-only flow.
- `/mempenny:memory-compress` respects existing MemPenny scope rules: skips `MEMORY.md`, `*.original.md`, `*.backup.md`, and anything under `archive/`.

### Notes
- No breaking changes. v0.2.1 behavior is preserved identically for users who don't run the new command.
- Caveman is an optional dependency, not a hard one. MemPenny never bundles caveman's compression logic — it invokes caveman's own skill.

## [0.2.1] — 2026-04-11

### Fixed
- `/memory-apply` now handles memory files that start with a `#` markdown heading instead of YAML frontmatter — the heading line is preserved, the body is replaced. Previously the behavior was ambiguous; the subagent tended to do the right thing but it was undocumented. Files with neither frontmatter nor a title heading have their entire contents replaced.
- `/memory-apply` prompt now explicitly warns the apply subagent against `((count++))` bash counters under `set -e` — they exit with code 1 on first increment and were producing spurious "failed" lines in the success report. The actual filesystem state was always correct, but the report was noisy. Use `count=$((count+1))` instead.

### Dogfood
- Plugin v0.2 validated end-to-end on two real auto-memory directories before release: one small (~13 KB, exercising the DISTILL + MEMORY.md-intact paths) and one large (~345 KB / 115 files, exercising DELETE + ARCHIVE + DISTILL + MEMORY.md-remove). All backup / delete / archive / distill / MEMORY.md update code paths verified against backups. Net auto-load reduction on the large dogfood target was 43%.

## [0.2.0] — 2026-04-11

### Added
- **Localization** — `--lang <code>` argument on all three commands, plus `MEMPENNY_LOCALE` environment variable. Triage and distill subagents write distilled replacements in the user's language; user-visible summary labels are also translated.
- **`--dir <path>` argument** on `/memory-triage` and `/memory-apply`. Lets you triage any memory directory without switching Claude Code sessions — no more fighting the auto-detection. If `--dir` was used for triage, the same `--dir` must be used for apply so the table aligns with the target.
- `locales/en/strings.json`, `locales/pt-BR/strings.json`, `locales/es/strings.json` shipped by default.
- `locales/README.md` — contributor guide for adding new locales. Uses BCP 47 language codes.
- `.claude-plugin/plugin.json` moved to the correct Claude Code plugin location and updated to match the marketplace schema (`author` as object, `version`, `license`, `keywords`).
- `.claude-plugin/marketplace.json` so the repo can act as its own marketplace (`/plugin marketplace add marcelopaniza/mempenny`).
- `LICENSE` (MIT).
- `CHANGELOG.md` (this file).
- `.gitignore` for common editor / OS / Python junk.
- README "Why MemPenny" section explaining long-running-project advantages.

### Changed
- Triage / apply / distill commands now have a locale-loading step before their existing logic. English remains the default; behavior is identical if `--lang` is not passed.
- `plugin.json` now lives at `.claude-plugin/plugin.json`. The old root-level `plugin.json` was removed.

### Notes
- No breaking changes for users who don't pass `--lang`. English is still the default, and every existing prompt still produces identical English output.

## [0.1.0] — 2026-04-11

Initial scaffold.

### Added
- `plugin.json` manifest.
- `commands/memory-triage.md` — dry-run triage, spawns an `Explore` subagent to produce a markdown table at `/tmp/triage_table.md`. No writes.
- `commands/memory-apply.md` — applies a previously approved triage table. Creates `memory.backup-YYYYMMDD/` before touching anything. Idempotent. Stops if ≥5% of any bucket fails.
- `commands/memory-distill.md` — one-off distillation of a single memory file.
- `skills/memory-hygiene/SKILL.md` — write-time discipline and strategy hierarchy documentation.
- `README.md` — user-facing explanation and the composability story with [caveman](https://github.com/JuliusBrussee/caveman).
