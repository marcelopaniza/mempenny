# MemPenny

**Your Claude memory companion. Turn it on, keep it lean, schedule the upkeep, reverse anything.**

Claude's memory grows. Old notes pile up. The signal gets buried. MemPenny tidies it — and Claude's next session starts sharper.

```
Before:  424 files · 1,247 KB loading every session
After:   227 files ·   458 KB · ~63% lighter
```

A real second-pass run; full case study: [Real-world results](docs/real-world-results.md).

Two ways:

- **Clean now** — `/mempenny:clean`. One command. Minute or two. You see the proposal, say yes, done.
- **Set a learning nap** — `/mempenny:nap`. Pick a schedule (daily / weekly / once). MemPenny tidies on your next Claude Code session — backup-first, no prompts, fully reversible. Each pass leaves Claude with cleaner notes to learn from next time.

What it does:

- Drops what's clearly stale.
- Files away historical stuff (still searchable, just out of the way).
- Trims bloated notes to one or two lines.
- Spots duplicates and keeps the best one.
- Flags files that contradict each other so you can sort them out.
- Organizes what's kept into a fixed set of topic files, so nothing sprawls into hundreds of one-off notes. *(New in v1.1 — existing projects convert automatically.)*
- Leaves alone files and folders you mark off-limits.

Don't like a change? `/mempenny:restore` puts everything back. Backup-first, always.

## Install

```
/plugin marketplace add marcelopaniza/mempenny
/plugin install mempenny@mempenny
/reload-plugins
```

---

# Advanced

## `/mempenny:clean` — clean now

One command, end-to-end:

```
/mempenny:clean
```

What happens, in order:

1. **Triages every memory file** — DELETE the obsolete, ARCHIVE the historical, DISTILL the bloated, KEEP the rest.
2. **Looks across files** — proposes DEDUPE when duplicates show up, MERGE when files cover the same topic from different angles, FLAG when files contradict each other.
3. **Shows you the proposal** — `Yes, apply` / `No, cancel` / `Show full table`. Nothing on disk changes until you say yes.
4. **Backs up first** — every change goes through a timestamped backup. Reversible via `/mempenny:restore`.

First run in a memory directory asks where to keep backups (defaults to a sibling folder next to the memory dir) and remembers the choice. Every subsequent run is one command.

**Roll back any time:**

```
/mempenny:restore
```

Lists backups, you pick one. The current state is snapshotted first — the restore itself is reversible.

---

## Topic-based organization

Starting in v1.1, MemPenny organizes what it keeps instead of just cleaning it. Every memory file lands in one of 8 fixed topics — a goal/requirements file, an in-flight-work file, a shipped-work log, a support log, a hazards file, a standing-rules file, a decisions log, and a reference/glossary file. Each has a defined job, so a fresh Claude session (or you, six months later) knows exactly where to look without reading eight files to find one fact.

**Existing projects convert automatically.** The next time you run `/mempenny:clean` on a memory directory still using the old one-file-per-memory layout, MemPenny migrates it: every existing file gets relocated — never deleted, never rewritten — into the right topic, verified line-for-line before anything old is removed, then reports what moved where. No prompt to click through; the backup and the verify-before-delete step are the safety net, not the click. Don't want this yet? `/mempenny:clean --no-migrate` opts a project out.

As topics grow, MemPenny keeps them from sprawling two different ways:

- **`/mempenny:memory-curate <file>`** — a rules/hazards/reference file that's grown large gets reviewed entry-by-entry (keep / archive / delete), not collapsed wholesale the way `/mempenny:memory-distill` would.
- **`/mempenny:memory-shard-roll <file>`** — a log file (shipped work, support history, decisions) that's grown large gets its finished years closed out into their own locked, permanent files, so the active file stays current-year-sized.

Both trigger automatically from `/mempenny:clean` when a topic file crosses its size ceiling, and both run through the same backup-first, verify-before-write discipline as everything else in MemPenny. Full design spec: [`docs/memory-taxonomy-design.md`](docs/memory-taxonomy-design.md).

---

## `/mempenny:nap` — schedule a learning nap

Pick a frequency and a time. MemPenny runs `/clean --yes` for you when the schedule fires — no prompt, just a clean memory waiting for you.

```
/mempenny:nap                 # configure: backup folder → frequency → time
/mempenny:nap --list          # show all configured schedules
/mempenny:nap --cancel        # remove the schedule for this memory dir
```

Three questions, no daemons, works with whatever auth Claude Code already uses — OAuth or API key, both fine. The hook installs with the plugin and never modifies your `~/.claude/settings.json` — MemPenny only writes that file when you explicitly accept the auto-memory enable offer.

When the schedule fires, MemPenny runs `/mempenny:clean --yes` on your next Claude Code session in this project — no Yes/No prompt, just a clean memory waiting for you. Backup-first, fully reversible via `/mempenny:restore`. **Uses Claude credits per fire** (same as a manual `/clean`).

Cross-platform: Linux + macOS for now. Windows support deferred.

---

## Flags on `/mempenny:clean`

- `--dir <path>` — operate on a memory directory other than the current project's.
- `--only <glob>` — restrict triage scope by filename glob. Comma-separate multiple globs. Example: `--only "project_*_20*.md,reference_*.md"`.
- `--lang <code>` — locale for user-visible output. Ships with `en`, `es`, `pt-BR`. Also honors `MEMPENNY_LOCALE`.
- `--reconfigure` — re-prompt for this memory directory's backup folder (ignores the saved entry). Other projects' entries are left alone.
- `--yes` — skip the confirmation gate; auto-apply after triage. Backup-first. This is what `/mempenny:nap` fires when the schedule runs.
- `--no-migrate` — opt this memory directory out of automatic topic-taxonomy migration, permanently (until you remove the flag by re-running without it). See [Topic-based organization](#topic-based-organization).

## Manual phases

- `/mempenny:memory-triage [--dir <path>] [--only <glob>] [--lang <code>]` — dry-run triage. Produces a markdown classification table at a private `mktemp` path with permissions `600`. No writes.
- `/mempenny:memory-apply <table-file> [--dir <path>] [--lang <code>]` — applies a previously approved triage table. Table path is required; pass the path printed by `/mempenny:memory-triage`. Creates a backup before modifying anything.
- `/mempenny:memory-distill <file> [--lang <code>]` — one-off distillation of a single file. Interactive: shows the proposal, asks to apply / skip / edit.
- `/mempenny:memory-curate <file> [--lang <code>] [--yes]` — entry-by-entry reduction for an over-ceiling `traps.md`/`rules.md`/`reference.md`. See [Topic-based organization](#topic-based-organization).
- `/mempenny:memory-shard-roll <file> [--lang <code>]` — closes finished calendar years out of an over-ceiling `worklog.md`/`support.md`/`decisions.md` into a locked yearly file. See [Topic-based organization](#topic-based-organization).

## Tell MemPenny what to leave alone

Lock a whole folder — drop an empty `.mempenny-lock` file in it:

```
touch .mempenny-lock
```

`/clean` and `/nap` refuse to touch anything inside.

Lock a single memory file — add this line at the top:

```
<!-- mempenny-lock -->
```

`/clean` treats it as KEEP and never proposes changes. Spacing inside the comment is flexible — `<!--mempenny-lock-->` and `<!-- mempenny-lock -->` both work.

Remove the marker (or the line) to unlock. The same `.mempenny-fixture` marker also locks a folder — kept around for test fixtures.

## Config file

MemPenny stores one small JSON file at `~/.claude/mempenny.config.json` mapping each memory directory to its backup folder, plus (since v1.1) each directory's topic-migration state:

```json
{
  "version": 2,
  "memory_dirs": {
    "/home/you/.claude/projects/-mnt-data-project-a/memory": "/home/you/.claude/projects/-mnt-data-project-a/memory.backups",
    "/home/you/.claude/projects/-mnt-data-project-b/memory": "/home/you/backups/mempenny-b"
  },
  "memory_layout": {
    "/home/you/.claude/projects/-mnt-data-project-a/memory": "topics"
  },
  "migrate_documents": {
    "/home/you/.claude/projects/-mnt-data-project-b/memory": false
  }
}
```

First run of `/mempenny:clean` (or `/mempenny:nap`) in a memory directory prompts for the folder and adds an entry. Other entries are preserved on every write. The file is `chmod 600`. `memory_layout` and `migrate_documents` entries only appear once relevant — a directory absent from both is still on the flat layout and still eligible for automatic migration (the default).

## Rollback — manual

Prefer `/mempenny:restore`. The paths below are for cases where that isn't an option.

**Backup path** (v0.5+): `<backup-folder>/memory.backup-YYYYMMDDHHMMSS-PID/`. The backup folder is whatever you configured for this memory directory.

```bash
# !!! REPLACE every <PLACEHOLDER> before running.
# <PROJECT_ID> = e.g. -mnt-data-myproject    (find it with: ls ~/.claude/projects/)
# <MEMORY_DIR> = ~/.claude/projects/<PROJECT_ID>/memory
# <BACKUP_FOLDER> = absolute path for this memory dir, read from the config:
#   jq -r --arg dir "<MEMORY_DIR>" '.memory_dirs[$dir]' ~/.claude/mempenny.config.json
# <TIMESTAMP> = 14-digit UTC timestamp of the backup dir (ls the backup folder)
# <PID> = numeric PID suffix (check the backup dir name)

rm -rf ~/.claude/projects/<PROJECT_ID>/memory/
mv "<BACKUP_FOLDER>/memory.backup-<TIMESTAMP>-<PID>/" ~/.claude/projects/<PROJECT_ID>/memory/
```

**If there's no config entry for this memory dir** (no config file, or v2 with no entry): `/mempenny:memory-apply` falls back to the legacy sibling path `<memory-dir>.backup-YYYYMMDDHHMMSS-PID/`. This fallback is NOT found by `/mempenny:restore` — add a config entry by running `/mempenny:clean` once.

## Backup retention

Backups accumulate and are never auto-deleted. Periodically prune:

```bash
# List all backups for a memory dir
MEMDIR=~/.claude/projects/<project-id>/memory
ls "$(jq -r --arg dir "$MEMDIR" '.memory_dirs[$dir]' ~/.claude/mempenny.config.json)"

# Legacy sibling backups (if any)
ls -d ~/.claude/projects/<project-id>/memory.backup-*/
```

Rule of thumb: keep the last 3–5 backups; delete anything older than ~2 weeks if nothing feels wrong.

## Localization

MemPenny ships with `en`, `es`, `pt-BR`. Pass `--lang <code>` or set `MEMPENNY_LOCALE`.

MemPenny translates **output** — the distilled memory replacements and user-visible summary — not its internal instructions to Claude. If your memories are in Portuguese, a triage pass produces Portuguese distillations. Technical terms (URLs, paths, commands, version numbers) are preserved verbatim.

Adding a new locale is a one-file PR: copy `locales/en/strings.json`, translate the values. Full guide in [`locales/README.md`](./locales/README.md).

## The strategy hierarchy

```
DELETE    →  zero tokens, zero loss if truly obsolete
ARCHIVE   →  move out of auto-load path, keep for forensics
DISTILL   →  replace narrative with 1-3 lines of forward-looking truth
DEDUPE    →  drop redundant copies, keep the newest
MERGE     →  combine related files into one
FLAG      →  alert you to contradicting files for manual review
KEEP      →  leave alone
```

The first three are per-file decisions made on every run. DEDUPE / MERGE / FLAG are cross-file decisions added in v0.9. KEEP is the default; nothing is removed unless MemPenny is confident AND you approve.

## How it works

Commands are markdown prompt templates that orchestrate AI subagents. `/mempenny:clean` runs a per-file triage subagent, then a cross-file cluster subagent, then an apply subagent — with a confirm gate before any write. Pass `--yes` to skip the confirm gate; this is what `/mempenny:nap` fires when the schedule runs. `/mempenny:nap` is a small bash hook (`hooks/nap-check.sh`) shipped with the plugin that fires on `SessionStart`, checks your schedule, and if it's time, runs `/mempenny:clean --yes` automatically. `/mempenny:restore` reads the backup index, takes a safety snapshot of the current state, and copies the chosen backup into place. Memory-* commands are the same building blocks exposed individually. Migration, `/mempenny:memory-curate`, and `/mempenny:memory-shard-roll` follow the same shape: a read-only subagent proposes, a separately-spawned apply subagent verifies and writes, and nothing old is removed until that verification passes.

The plugin is markdown command files, three JSON locale files, a small bash hook, and a plugin manifest. Everything stays on your machine — nothing is sent over the network.

## Locked surface (v1.0+)

From v1.0, MemPenny commits to semver. Breaking changes only on major bumps.

**Stable:**
- Command names and their argument shapes (`/mempenny:clean`, `/mempenny:nap`, `/mempenny:restore`, `/mempenny:memory-triage`, `/mempenny:memory-apply`, `/mempenny:memory-distill`)
- Config schema v2 (`~/.claude/mempenny.config.json`)
- Backup directory format (`<backup-folder>/memory.backup-YYYYMMDDHHMMSS-PID/`)
- Locale key shape — new keys may be added; existing keys keep their meaning
- Lock conventions: `.mempenny-lock`, `.mempenny-fixture`, `<!-- mempenny-lock -->`

**Not stable (internal):**
- Subagent prompts and rubric internals
- Confidence tiers and overlap thresholds
- Exact output wording (beyond locale keys)
- Hardening implementation details

If we need to change anything in Stable, it's a v2.0.

## Requirements

- Claude Code with auto-memory enabled. (MemPenny detects if it's off and offers to turn it on.)

## License

MIT — see [LICENSE](./LICENSE).
