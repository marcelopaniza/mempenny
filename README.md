# MemPenny

**Memory hygiene for any AI coding agent. Turn it on, keep it lean, schedule the upkeep, reverse anything.**

[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-1.2.0-blue.svg)](CHANGELOG.md)
[![Platform](https://img.shields.io/badge/platform-Claude%20Code%20%C2%B7%20opencode-orange.svg)](#install)
[![Backups](https://img.shields.io/badge/backups-always%20first-yellow.svg)](SECURITY.md)
[![Locales](https://img.shields.io/badge/locales-3%20languages-blue.svg)](locales/README.md)

Your agent's memory grows. Old notes pile up. The signal gets buried. MemPenny tidies it — and the next session starts sharper.

It runs on **Claude Code** and **opencode**, and any agent that reads an `AGENTS.md` (Codex, Gemini, CodeWhale, Swival, Cursor, Windsurf, and friends). Same memory directory, same commands, same safety net. If you switch hosts mid-project, the tidied memory comes with you.

## Before / after

| | Files | Size |
|---|---:|---:|
| Before | 424 | 1,247 KB |
| After | 227 | 458 KB |
| **Change** | **−46%** | **−63%** |

A real second-pass run on a real memory directory. Full case study: [docs/real-world-results.md](docs/real-world-results.md).

## Two ways to use it

- **Clean now** — one command. You see the proposal, you say yes, done. A minute or two.
- **Set a nap** — pick a schedule (daily / weekly / once). MemPenny tidies on your next session. Backup-first, no prompts, fully reversible.

## What it does

- Drops what's clearly stale.
- Files the historical stuff away (still searchable, just out of the way).
- Trims bloated notes to a line or two.
- Spots duplicates and keeps the best one.
- Flags files that contradict each other so you can sort them out.
- Keeps what's left in a small, fixed set of topic files — nothing sprawls into hundreds of one-off notes.
- Leaves alone anything you mark off-limits.

Don't like a change? One command puts everything back. Backup-first, always.

## Install

**Claude Code**

```
/plugin marketplace add marcelopaniza/mempenny
/plugin install mempenny@mempenny
/reload-plugins
```

**opencode** (available from v1.2.0)

```bash
git clone https://github.com/marcelopaniza/mempenny.git
cd mempenny && git checkout v1.2.0
./install/opencode.sh
```

Commands are `/mempenny-clean`, `/mempenny-nap`, `/mempenny-restore`, `/mempenny-memory-*` (hyphen, not colon). If you also run Claude Code in this project, the two hosts share the same memory directory and config automatically — zero setup.

**Other agents** — Codex, Gemini, CodeWhale, Swival, Cursor, Windsurf, …

Copy [`AGENTS.md`](AGENTS.md) into your project root. That carries the ruleset: the strategy hierarchy (delete > archive > distill > keep), the safety guards, and the write-time discipline. No hooks and no auto-schedule on this tier — you run the cleanup yourself, following the guide. Full matrix and rationale: [docs/host-and-model-compat.md](docs/host-and-model-compat.md).

## Supported hosts & models

| Host | Clean / Restore | Scheduled nap |
|---|:---:|:---:|
| Claude Code | ✅ | ✅ |
| opencode | ✅ | ✅ |
| Any `AGENTS.md` reader | rules-only | — |

On opencode, a scheduled nap fires a desktop notification pointing at `/mempenny-clean`; auto-invoke is reserved for a future release.

MemPenny is tuned on Claude Sonnet/Opus and runs on GLM 4.6+, GPT-5, and Gemini 2.5. **Conservation is non-negotiable on every model** — a scripted check verifies nothing is lost before anything old is deleted. Distillation quality varies by model; see the compat doc for per-model notes.

## Commands

| Command | What it does |
|---|---|
| `/mempenny-clean` | One-shot tidy: triage → show → apply. Backup-first. |
| `/mempenny-nap` | Schedule a recurring clean. |
| `/mempenny-restore` | Reverse any pass. |
| `/mempenny-memory-triage` | Dry-run: propose actions, change nothing. |
| `/mempenny-memory-apply` | Apply a triage table. |
| `/mempenny-memory-distill` | Shrink one file to its load-bearing lines. |
| `/mempenny-memory-curate` | Reduce a topic file entry-by-entry. |
| `/mempenny-memory-shard-roll` | Close a finished year into a locked shard. |

Claude Code uses the colon namespace (`/mempenny:clean`, etc.) — same commands, two spellings.

## Safety, in one screen

- **Backup-first.** Every change is preceded by a full backup. `/mempenny-restore` reverses anything.
- **Nothing lost.** A scripted conservation check runs before any old file is deleted.
- **Path-locked.** Tight validation on every path and filename; symlinks refused at sensitive points.
- **Off-limits by default.** A `.mempenny-lock` file or a `<!-- mempenny-lock -->` comment opts anything out.

Full threat model and every codenamed guard: [SECURITY.md](SECURITY.md).

## Advanced

Full command reference, flags, config schema, the topic taxonomy, backup retention, localization, and how it all works under the hood: **[docs/advanced.md](docs/advanced.md)**.

## License

MIT — see [LICENSE](./LICENSE).
