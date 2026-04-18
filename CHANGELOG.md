# Changelog

All notable changes to MemPenny are documented here. This project follows [semantic versioning](https://semver.org/).

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
- Old backups created by `/mempenny:memory-apply` (date-only suffix, sibling path) are untouched and remain rollback-able by hand.
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
