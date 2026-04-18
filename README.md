# MemPenny

**Keep your Claude Code auto-memory lean.**

MemPenny triages your auto-memory directory: it deletes what's obsolete, archives what's historical, distills what's bloated, and leaves the rest alone. Pairs with [caveman](https://github.com/JuliusBrussee/caveman) — caveman compresses prose, MemPenny removes what shouldn't be there in the first place.

## The strategy hierarchy

```
DELETE    →  zero tokens, zero loss if truly obsolete
ARCHIVE   →  move out of auto-load path, keep for forensics
DISTILL   →  replace narrative with 1-3 lines of forward-looking truth
COMPRESS  →  caveman's job, out of scope for MemPenny
KEEP      →  leave alone
```

MemPenny owns the first three. Caveman owns the fourth. The fifth is the default.

## The pitch

> **MemPenny removes what doesn't need to be there. Caveman compresses what's left.**

```
┌────────────┐  ┌────────────┐  ┌────────────┐  ┌────────────┐
│  MemPenny  │→ │  MemPenny  │→ │  MemPenny  │→ │  Caveman   │
│   delete   │  │  archive   │  │  distill   │  │  compress  │
└────────────┘  └────────────┘  └────────────┘  └────────────┘
```

## Why MemPenny — the long-project advantage

Claude Code's auto-memory is loaded on **every** conversation in a project. Every byte you let rot there you pay for in tokens, latency, and model confusion — for the entire life of the project.

Short projects rarely feel it. Long projects drown in it. On a real project memory dir that had accumulated ~200 files / 366 KB over a few months, the first MemPenny pass cut the auto-load path by **55%** with zero information loss — purely by removing resolved-bug postmortems, dated test runs, and superseded architecture notes that the code itself had already become authoritative for.

The concrete advantages on a long-running project:

1. **Lower per-conversation token cost.** Every conversation starts ~55% smaller after a triage. Over thousands of conversations, that's real money and real latency — and it never stops paying back until you add new rot.
2. **Sharper model attention.** A bloated memory is noise. Stale postmortems "remind" Claude of fixes that are already in the code, causing it to mis-diagnose, re-apply old fixes, or mention features that no longer exist. Removing rot makes the model sharper, not just cheaper.
3. **Forward-looking truth by default.** MemPenny's DISTILL action replaces narrative prose ("we investigated X, found Y, did Z") with a 1–3 sentence statement of what's *now true*. That's the only form of memory that doesn't eventually lie to future-you.
4. **Backup-first, zero-loss by design.** Every apply pass creates a timestamped backup before touching anything (under `{backup_folder}` when a config exists, or as a sibling directory otherwise). If a distillation turns out wrong, you roll back via `/mp:restore` or a two-line shell command. The conservative bias is baked in — DELETE is the rarest action, not the default.
5. **Composes cleanly with caveman.** Triage first (remove what shouldn't be there), then compress what survives. Stacking both tools on the real memory dir above dropped it from 366 KB to well under 100 KB — a 75%+ reduction on the auto-load path, entirely through lossless structural changes plus caveman's linguistic compression.
6. **No Python, no scripts, no install friction.** MemPenny is all prompt templates. Two slash commands and you're done — no `pip install`, no script permissions, no runtime to maintain.
7. **Localized so the memory stays in your language.** If your memories are in Portuguese, the distilled replacements stay in Portuguese. See [Localization](#localization) below.

**The rule of thumb:** run `/mp:clean` once a month on any project older than a few months. The pass is ~6 minutes of subagent time and almost always finds 30–60% savings.

## Install

```
/plugin marketplace add marcelopaniza/mempenny
/plugin install mp@mempenny
/reload-plugins
```

After install, all commands are namespaced under `mp:` — invoke them as `/mp:clean`, `/mp:restore`, `/mp:memory-triage`, etc. The short `mp:` prefix is the invocation namespace; the marketplace entry is still `marcelopaniza/mempenny` for discovery.

> **Upgrading from 0.3.x?** Reinstall — the namespace changed from `/mempenny:…` to `/mp:…`. Your existing backups are untouched.

## Commands

**Everyday (start here):**

- `/mp:clean [--dir <path>] [--only <glob>] [--lang <code>] [--reconfigure]` — one-shot cleanup: triage + apply in a single pass with one confirm gate. First run prompts for a backup folder and saves the choice. Subsequent runs are one command.
- `/mp:restore [<backup-name>|latest] [--dir <path>] [--lang <code>]` — restore a backup created by `/mp:clean`. Takes a safety snapshot of the current state before overwriting, so the restore itself is reversible.

**Advanced (run each phase manually):**

- `/mp:memory-triage [--dir <path>] [--only <glob>] [--lang <code>]` — dry-run triage of a memory dir. Produces a markdown table at a private `mktemp` path (printed in the summary) with permissions `600`. No writes to the memory dir. Defaults to the current project's memory dir; `--dir` points it anywhere.
- `/mp:memory-apply <table-file> [--dir <path>] [--lang <code>]` — applies a previously approved triage table. The table path is **required** (v0.4.1+) — pass the path printed by `/mp:memory-triage`. Backs up first. Rolls-back policy on failure. Use the same `--dir` you passed to `memory-triage`.
- `/mp:memory-distill <file> [--lang <code>]` — one-off distillation of a single memory file. Interactive: shows the proposal, asks to apply / skip / edit.
- `/mp:memory-compress [--dir <path>] [--only <glob>] [--lang <code>]` — invokes [caveman](https://github.com/JuliusBrussee/caveman)'s `compress` skill on each surviving memory file in the directory. Shrinks prose while preserving code, commands, URLs, paths, and version numbers. Requires caveman installed; falls back to install instructions if not.

## Quick start

**Everyday flow (one command):**

```
/mp:clean
# First run: prompts you for a backup folder (default: <memory-dir>.backups/)
# Shows proposed changes, asks "Apply these changes?", then does it
# Subsequent runs reuse the saved backup folder — no prompt
```

**Roll back if something feels wrong:**

```
/mp:restore
# Lists backups, you pick one; current state is snapshotted first (reversible)
/mp:restore latest    # non-interactive: restore most recent backup
```

**Full three-step flow (manual, for power users who want to review the triage table):**

```
/mp:memory-triage
# Review the proposed table at the mktemp path it printed (e.g. /tmp/mempenny-triage-AbCdEfGh.md)

/mp:memory-apply /tmp/mempenny-triage-AbCdEfGh.md
# Backup created, obsolete/archived files removed, bloated files distilled

/mp:memory-compress
# Caveman compresses prose in every surviving file (leaves code/URLs/paths alone)
```

**Minimum flow (triage only, no writes):**

```
/mp:memory-triage
# Review table, decide if the savings are worth it, stop here if not
```

Want to target a subset?

```
/mp:clean --only "project_*_20*.md,reference_*.md"
```

Want to clean a different project's memory dir without switching sessions?

```
/mp:clean --dir /home/you/.claude/projects/-mnt-data-otherproject/memory/
```

Working in Portuguese or Spanish?

```
/mp:clean --lang pt-BR
/mp:clean --lang es
```

Or set it once and forget:

```
export MEMPENNY_LOCALE=pt-BR
```

## Localization

MemPenny ships with `en`, `pt-BR`, and `es` out of the box. Pass `--lang <code>` to any command, or set `MEMPENNY_LOCALE` in your environment.

Adding a new locale is a one-file PR — copy `locales/en/strings.json`, translate the values, open a pull request. Full guide in [`locales/README.md`](./locales/README.md).

The key insight: MemPenny doesn't translate its instructions to Claude (those are internal and work fine in English). It translates the **output** — the distilled memory replacements and the user-visible summary. If your memories are in Portuguese, a triage pass produces Portuguese distillations. Technical terms (URLs, file paths, commands, version numbers) are always preserved verbatim.

## How it works

All commands are prompt templates. `/mp:clean` orchestrates a triage subagent and an apply subagent back-to-back with a confirm gate between them, and remembers your backup folder in `~/.claude/mempenny.config.json` so future runs are one command. `/mp:restore` lists backups, takes a safety snapshot of the current state, and copies a chosen backup into place. Under the hood, `/mp:memory-triage` spawns a read-only `Explore` subagent that returns a markdown classification table; `/mp:memory-apply` spawns a general-purpose subagent that performs the `rm` / `mv` / body-replace operations, after creating a full backup. `/mp:memory-distill` is interactive and runs in the main conversation — no subagent.

There's no Python, no shell scripts, no daemon. The whole plugin is markdown command files, three JSON locale files, and a plugin manifest.

## Requirements

- Claude Code with auto-memory enabled
- No other dependencies

## Rollback

**If you used `/mp:clean`**: run `/mp:restore` and pick the backup you want. It snapshots the current state first, so the restore itself is reversible.

**If you used `/mp:memory-apply` with a config present** (`~/.claude/mempenny.config.json`): the backup goes to `{backup_folder}/memory.backup-YYYYMMDDHHMMSS-PID/` — the same root that `/mp:clean` uses. Run `/mp:restore` to list and restore it interactively — strongly preferred over hand-rolling. If you insist on manual rollback:

```bash
# !!! REPLACE every <PLACEHOLDER> before running. Running this literally will silently fail
# !!! (the angle-bracket paths don't exist), but DO NOT paste into a shell without replacing.
# <PROJECT_ID> = e.g. -mnt-data-myproject    (find it with: ls ~/.claude/projects/)
# <BACKUP_FOLDER> = absolute path from: jq -r .backup_folder ~/.claude/mempenny.config.json
# <TIMESTAMP> = the exact 14-digit UTC timestamp of the backup dir (ls your backup folder)
# <PID> = the numeric PID suffix (check the backup dir name)

rm -rf ~/.claude/projects/<PROJECT_ID>/memory/
mv "<BACKUP_FOLDER>/memory.backup-<TIMESTAMP>-<PID>/" ~/.claude/projects/<PROJECT_ID>/memory/
```

**If you used `/mp:memory-apply` without a config** (no `~/.claude/mempenny.config.json`): the backup falls back to the legacy sibling path `<memory-dir>.backup-YYYYMMDDHHMMSS-PID/`. Roll back by hand:

```bash
# !!! Same placeholder caveat as above.
rm -rf ~/.claude/projects/<PROJECT_ID>/memory/
mv ~/.claude/projects/<PROJECT_ID>/memory.backup-<TIMESTAMP>-<PID>/ ~/.claude/projects/<PROJECT_ID>/memory/
```

This fallback path is NOT found by `/mp:restore` (which only scans `{backup_folder}`). Run `/mp:clean` once to set up a config and all future `/mp:memory-apply` backups will go to the unified location.

### Backup retention

Backups accumulate and are never deleted automatically. Periodically prune old ones you no longer need:

```bash
# List all backups in the configured folder
ls $(jq -r .backup_folder ~/.claude/mempenny.config.json)

# List legacy sibling backups (if any)
ls -d ~/.claude/projects/<project-id>/memory.backup-*/
```

A safe rule of thumb: keep the last 3–5 backups and delete anything older than 2 weeks if nothing feels wrong.

## After MemPenny: compress with caveman

MemPenny removes what shouldn't be there. [Caveman](https://github.com/JuliusBrussee/caveman) compresses what's left — stripping prose padding while preserving code, commands, URLs, paths, frontmatter, and version numbers exactly. Running both in sequence is the full story.

**If caveman is already installed**, just run `/mp:memory-compress` after a clean or apply. MemPenny invokes `caveman:compress` on each surviving file individually, tracks total bytes saved, and reports back. Each file gets its own per-file backup at `<filename>.original.md` (created by caveman, not MemPenny) so rollback is one `mv` per file.

**If caveman isn't installed**, MemPenny detects that, prints the install commands, and stops without modifying anything:

```
/plugin marketplace add JuliusBrussee/caveman
/plugin install caveman@caveman
/reload-plugins
```

Then re-run `/mp:memory-compress`. The graceful-fallback design means MemPenny works fully without caveman — the composability is opt-in, not a hard dependency.

**Typical stacking result on a long-running project:** MemPenny alone cuts auto-load by ~30–55% (deletes + archives + distillations). Running caveman on the KEEP survivors adds another ~30–40% on top through prose compression. Together: often 60–75% off the auto-load path with zero technical loss.

## See also

- [caveman](https://github.com/JuliusBrussee/caveman) — the prose compressor MemPenny pairs with. MemPenny removes; caveman compresses.

## License

MIT — see [LICENSE](./LICENSE).
