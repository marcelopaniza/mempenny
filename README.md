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
4. **Backup-first, zero-loss by design.** Every apply pass creates `memory.backup-YYYYMMDD/` before touching anything. If a distillation turns out wrong, you roll back with a two-line command. The conservative bias is baked in — DELETE is the rarest action, not the default.
5. **Composes cleanly with caveman.** Triage first (remove what shouldn't be there), then compress what survives. Stacking both tools on the real memory dir above dropped it from 366 KB to well under 100 KB — a 75%+ reduction on the auto-load path, entirely through lossless structural changes plus caveman's linguistic compression.
6. **No Python, no scripts, no install friction.** MemPenny is all prompt templates. Two slash commands and you're done — no `pip install`, no script permissions, no runtime to maintain.
7. **Localized so the memory stays in your language.** If your memories are in Portuguese, the distilled replacements stay in Portuguese. See [Localization](#localization) below.

**The rule of thumb:** run `/mempenny:memory-triage` once a month on any project older than a few months. The pass is ~6 minutes of subagent time and almost always finds 30–60% savings.

## Install

```
/plugin marketplace add marcelopaniza/mempenny
/plugin install mempenny@mempenny
/reload-plugins
```

After install, the three commands are namespaced under `mempenny:` — always invoke them as `/mempenny:memory-triage`, `/mempenny:memory-apply`, `/mempenny:memory-distill`. The bare form (`/memory-triage`) may or may not resolve depending on your other installed plugins; the namespaced form always works.

## Commands

- `/mempenny:memory-triage [--dir <path>] [--only <glob>] [--lang <code>]` — dry-run triage of a memory dir. Produces a markdown table at `/tmp/triage_table.md`. No writes. Defaults to the current project's memory dir; `--dir` points it anywhere.
- `/mempenny:memory-apply [<table-file>] [--dir <path>] [--lang <code>]` — applies a previously approved triage table. Backs up first. Rolls back policy on failure. Use the same `--dir` you passed to `memory-triage`.
- `/mempenny:memory-distill <file> [--lang <code>]` — one-off distillation of a single memory file. Interactive: shows the proposal, asks to apply / skip / edit.

## Quick start

```
/mempenny:memory-triage
# Review the proposed table at /tmp/triage_table.md
/mempenny:memory-apply /tmp/triage_table.md
```

Want to target a subset?

```
/mempenny:memory-triage --only "project_*_20*.md,reference_*.md"
```

Want to triage a different project's memory dir without switching sessions?

```
/mempenny:memory-triage --dir /home/you/.claude/projects/-mnt-data-otherproject/memory/
```

Working in Portuguese or Spanish?

```
/mempenny:memory-triage --lang pt-BR
/mempenny:memory-triage --lang es
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

All three commands are prompt templates. `/memory-triage` spawns a read-only `Explore` subagent that reads every file in scope and returns a markdown classification table. `/memory-apply` spawns a general-purpose subagent that performs the `rm` / `mv` / body-replace operations listed in the table, after creating a full backup. `/memory-distill` is interactive and runs in the main conversation — no subagent.

There's no Python, no shell scripts, no daemon. The whole plugin is five markdown files, three JSON locale files, and a plugin manifest.

## Requirements

- Claude Code with auto-memory enabled
- No other dependencies

## Rollback (if something goes wrong after `/memory-apply`)

Every apply creates a full backup at `<memory-dir>.backup-YYYYMMDD/`. To roll back:

```bash
rm -rf ~/.claude/projects/<project-id>/memory/
mv ~/.claude/projects/<project-id>/memory.backup-YYYYMMDD/ ~/.claude/projects/<project-id>/memory/
```

Delete the backup after ~2 weeks if nothing feels wrong.

## See also

- [caveman](https://github.com/JuliusBrussee/caveman) — compress the prose in memories that survive MemPenny triage. The two tools are designed to stack.

## License

MIT — see [LICENSE](./LICENSE).
