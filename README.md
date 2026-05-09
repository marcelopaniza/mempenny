# MemPenny

**Keep your Claude memory tight.**

Triage, dedupe, and merge your auto-memory directory. Clean it now with `/mempenny:clean`, or schedule a nap with `/mempenny:nap`. Backup-first, always — every change waits for your nod.

## Install

```
/plugin marketplace add marcelopaniza/mempenny
/plugin install mempenny@mempenny
/reload-plugins
```

---

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

## `/mempenny:nap` — schedule it

Set a frequency and a time. MemPenny runs `/clean` for you when the schedule fires.

```
/mempenny:nap                 # configure: backup folder → frequency → time
/mempenny:nap --list          # show all configured schedules
/mempenny:nap --cancel        # remove the schedule for this memory dir
```

Three questions, no daemons, works with whatever auth Claude Code already uses — OAuth, API key, both fine. The hook installs with the plugin and never modifies your `~/.claude/settings.json`.

Nap fires the next time you open Claude Code in this project after the scheduled time. Same `/clean` you already trust — same dry-run, same Yes / No / Show full gate, same backup-first behavior. **Uses Claude credits per fire** (same as a manual `/clean`).

Cross-platform: Linux + macOS for now. Windows support deferred.

---

# Advanced

## Flags on `/mempenny:clean`

- `--dir <path>` — operate on a memory directory other than the current project's.
- `--only <glob>` — restrict triage scope by filename glob. Comma-separate multiple globs. Example: `--only "project_*_20*.md,reference_*.md"`.
- `--lang <code>` — locale for user-visible output. Ships with `en`, `es`, `pt-BR`. Also honors `MEMPENNY_LOCALE`.
- `--reconfigure` — re-prompt for this memory directory's backup folder (ignores the saved entry). Other projects' entries are left alone.

## Manual phases

- `/mempenny:memory-triage [--dir <path>] [--only <glob>] [--lang <code>]` — dry-run triage. Produces a markdown classification table at a private `mktemp` path with permissions `600`. No writes.
- `/mempenny:memory-apply <table-file> [--dir <path>] [--lang <code>]` — applies a previously approved triage table. Table path is required; pass the path printed by `/mempenny:memory-triage`. Creates a backup before modifying anything.
- `/mempenny:memory-distill <file> [--lang <code>]` — one-off distillation of a single file. Interactive: shows the proposal, asks to apply / skip / edit.

## Config file

MemPenny stores one small JSON file at `~/.claude/mempenny.config.json` mapping each memory directory to its backup folder:

```json
{
  "version": 2,
  "memory_dirs": {
    "/home/you/.claude/projects/-mnt-data-project-a/memory": "/home/you/.claude/projects/-mnt-data-project-a/memory.backups",
    "/home/you/.claude/projects/-mnt-data-project-b/memory": "/home/you/backups/mempenny-b"
  }
}
```

First run of `/mempenny:clean` (or `/mempenny:nap`) in a memory directory prompts for the folder and adds an entry. Other entries are preserved on every write. The file is `chmod 600`.

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

Commands are markdown prompt templates that orchestrate AI subagents. `/mempenny:clean` runs a per-file triage subagent, then a cross-file cluster subagent, then an apply subagent — with a confirm gate before any write. `/mempenny:nap` is a small bash hook (`hooks/nap-check.sh`) shipped with the plugin that fires on `SessionStart`, checks your schedule, and if it's time, nudges Claude Code to run `/clean`. `/mempenny:restore` reads the backup index, takes a safety snapshot of the current state, and copies the chosen backup into place. Memory-* commands are the same building blocks exposed individually.

The plugin is markdown command files, three JSON locale files, a small bash hook, and a plugin manifest. Everything stays on your machine — nothing is sent over the network.

## Requirements

- Claude Code with auto-memory enabled.

## License

MIT — see [LICENSE](./LICENSE).
