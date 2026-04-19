# MemPenny

**Keep your Claude Code auto-memory lean.**

MemPenny triages your auto-memory directory: it deletes what's obsolete, archives what's historical, distills what's bloated, and leaves the rest alone. If [terse-md](https://github.com/marcelopaniza/terse-md) is installed, MemPenny can hand off to it at the end of a clean for a second, prose-level compression pass.

## Install

```
/plugin marketplace add marcelopaniza/mempenny
/plugin install mp@mempenny
/reload-plugins
```

Commands are namespaced under `mp:` — invoke them as `/mp:clean`, `/mp:restore`, etc.

> **Upgrading from 0.3.x?** Reinstall — the namespace changed from `/mempenny:…` to `/mp:…`. Existing backups are untouched.

---

# Default

**One command, end-to-end:**

```
/mp:clean
```

That's it. On first run in a memory directory, MemPenny asks where to put backups (defaults to a sibling folder next to the memory dir) and remembers the choice. Every subsequent run in that directory is one command.

What `/mp:clean` does, in order:

1. Runs a dry-run triage of the memory directory and prints a summary.
2. Asks you to confirm.
3. Creates a timestamped backup.
4. Applies the approved changes (deletes, archives, distillations).
5. If [terse-md](https://github.com/marcelopaniza/terse-md) is installed, the apply prompt offers a fourth option — `Yes, apply + run terse-md after` — and MemPenny hands off to terse-md only if you pick it. If terse-md is not installed, MemPenny prints a short note after the apply — you can install terse-md and re-run compress later, or skip it. Nothing is missing either way.

**Roll back if something feels wrong:**

```
/mp:restore
```

Lists backups, you pick one. The current state is snapshotted first, so the restore itself is reversible.

**That's the whole story for most users.** The rest of this README is optional.

---

# Advanced

## Commands (manual phases)

- `/mp:memory-triage [--dir <path>] [--only <glob>] [--lang <code>]` — dry-run triage. Produces a markdown classification table at a private `mktemp` path with permissions `600`. No writes.
- `/mp:memory-apply <table-file> [--dir <path>] [--lang <code>]` — applies a previously approved triage table. Table path is required; pass the path printed by `/mp:memory-triage`. Creates a backup before modifying anything.
- `/mp:memory-distill <file> [--lang <code>]` — one-off distillation of a single file. Interactive: shows the proposal, asks to apply / skip / edit.
- `/mp:memory-compress [--dir <path>] [--lang <code>] [--dry-run] [--include-all]` — thin router to terse-md. Detects `/terse-md:run`; invokes it on the memory directory if installed, otherwise prints an install hint and stops. MemPenny does not modify any file in this command.

## Flags on `/mp:clean`

- `--dir <path>` — operate on a memory directory other than the current project's.
- `--only <glob>` — restrict triage scope by filename glob. Comma-separate multiple globs. Example: `--only "project_*_20*.md,reference_*.md"`.
- `--lang <code>` — locale for user-visible output. Ships with `en`, `es`, `pt-BR`. Also honors `MEMPENNY_LOCALE`.
- `--reconfigure` — re-prompt for this memory directory's backup folder (ignores the saved entry). Other projects' entries are left alone.

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

First run of `/mp:clean` in a memory directory prompts for the folder and adds an entry. Other entries are preserved on every write. The file is `chmod 600`.

**Upgrading from v0.4.x** (single global `backup_folder`): the config is auto-migrated on first `/mp:clean` run. The old global path is preserved for the current memory directory only; other projects get their own prompt next time you clean them.

## Calling terse-md manually

`/mp:clean` offers to chain to terse-md when it's installed (via a fourth option on the apply prompt). You can also run terse-md directly, any time:

```
/terse-md:run --all /path/to/memory
```

Terse-md compresses each Markdown file to a validated YAML sibling (`<name>.approved.yaml`). It runs its own per-file review and never overwrites the source. See [terse-md's README](https://github.com/marcelopaniza/terse-md) for its own flags and behavior.

**If terse-md isn't installed and you want to install it:**

```
/plugin marketplace add marcelopaniza/terse-md
/plugin install terse-md@marcelopaniza-terse-md
/reload-plugins
```

## Rollback — manual

Prefer `/mp:restore`. The paths below are for cases where that isn't an option.

**Backup path for a memory dir with a v2 config entry** (v0.5+): `<backup-folder>/memory.backup-YYYYMMDDHHMMSS-PID/`. The backup folder is whatever you configured for this memory directory.

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

**If your config is still v1** (a v0.4.x `backup_folder` not yet migrated): the backup is at the global path. Read it with `jq -r .backup_folder ~/.claude/mempenny.config.json`. Running `/mp:clean` once auto-migrates to v2.

**If there's no config entry for this memory dir** (no config file, or v2 with no entry): `/mp:memory-apply` falls back to the legacy sibling path `<memory-dir>.backup-YYYYMMDDHHMMSS-PID/`. This fallback is NOT found by `/mp:restore` — add a config entry by running `/mp:clean` once.

## Backup retention

Backups accumulate and are never auto-deleted. Periodically prune:

```bash
# List all backups for a memory dir (v0.5+)
MEMDIR=~/.claude/projects/<project-id>/memory
ls "$(jq -r --arg dir "$MEMDIR" '.memory_dirs[$dir]' ~/.claude/mempenny.config.json)"

# v1 legacy config
ls "$(jq -r .backup_folder ~/.claude/mempenny.config.json)"

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
KEEP      →  leave alone
COMPRESS  →  terse-md's job, out of scope for MemPenny
```

MemPenny owns the first three. The fourth is the default. The fifth is optional and lives outside MemPenny.

## How it works

All commands are prompt templates. `/mp:clean` orchestrates a triage subagent and an apply subagent back-to-back with a confirm gate between them, remembers your backup folder **per memory directory** in `~/.claude/mempenny.config.json`, and optionally chains to terse-md at the end. `/mp:restore` lists backups, takes a safety snapshot, and copies a chosen backup into place. `/mp:memory-triage` spawns a read-only `Explore` subagent. `/mp:memory-apply` spawns a general-purpose subagent for the `rm` / `mv` / body-replace operations after creating a backup. `/mp:memory-distill` is interactive and runs in the main conversation.

No Python, no scripts, no daemon. The plugin is markdown command files, three JSON locale files, and a plugin manifest.

## Requirements

- Claude Code with auto-memory enabled
- No other dependencies. (Terse-md is optional; its absence is a no-op.)

## See also

- [terse-md](https://github.com/marcelopaniza/terse-md) — the Markdown → validated YAML compressor MemPenny optionally hands off to at the end of a clean.

## License

MIT — see [LICENSE](./LICENSE).
