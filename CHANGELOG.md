# Changelog

All notable changes to MemPenny are documented here. This project follows [semantic versioning](https://semver.org/).

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
