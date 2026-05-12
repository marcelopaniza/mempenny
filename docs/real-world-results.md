# Real-world results: a second-pass cleanup

A user ran `/mempenny:clean` on a memory directory that had already been cleaned once. The directory had grown to ~1.25 MB (1,247 KB) across 424 files since the previous pass. The numbers below are from that second run.

## Before / after

| | Before | After |
|---|---|---|
| Top-level `.md` files | 424 | 227 |
| Auto-loaded into every Claude session | ~1,247 KB | ~458 KB |
| Net savings | — | ~789 KB (~63%) |
| `MEMORY.md` index | 280 lines | 260 lines |
| Files moved to `archive/` (this run) | — | +198 |
| `archive/` total size after this run | — | ~966 KB |
| Files merged | 0 | 1 cluster (2 → 1) |
| Files flagged for manual review | 0 | 1 cluster |

The 198 archived files are still on disk under `<memory-dir>/archive/` — just out of the auto-load path. Nothing was deleted on this run.

The `MEMORY.md` index only shrank by 20 lines because most of the 198 archived files had already aged off the index in earlier runs — `MEMORY.md` tracks currently-pointed-at memories, not every file on disk. Archive activity and index activity are loosely coupled, not 1:1.

## What's load-bearing in these numbers

**The savings come from archiving, not deletion.** This run had 0 deletes. Every byte saved came from moving historical postmortems out of the auto-load path. Forensic value preserved; per-session tax gone.

**A second pass still earned its keep.** The directory had been cleaned before; the user kept working, the directory kept growing, and the second pass freed ~789 KB. Treat `/mempenny:clean` as recurring maintenance, not a one-shot. `/mempenny:nap` exists for exactly this reason.

**1 MERGE landed.** Two related `feedback_*` files about model selection — one saying "default to Sonnet for everything", another laying out when to escalate to Opus — were combined into a single source-of-truth file. The two originals went to `archive/`. One topic, one file, one place Claude looks.

## Two honest notes

### FLAG can produce false positives — treat it as "needs your eyes"

The run flagged one pair of files as having "contradictory factual claims." On manual inspection: the older file's own frontmatter already documented that it had been superseded and named the newer file as the resolution. Not a real contradiction; documented succession that the cross-file pass didn't notice.

MemPenny now recognizes this pattern — when one file already documents that it's been superseded by another, the pair no longer raises FLAG. If you see a FLAG on your run, open the older file's frontmatter first; if it already names a successor, the succession is in place and you can safely archive the older one.

### DISTILL is harder than ARCHIVE

The dry-run proposed several DISTILL actions where the suggested 1–3 sentence replacement didn't fully capture the load-bearing facts in the original. Rather than risk losing information, those candidates were promoted to ARCHIVE — the file is still on disk, just out of the auto-load path. You can re-DISTILL individual files later with `/mempenny:memory-distill <file>` and inspect each proposal one at a time.

**Rule of thumb:** DISTILL asks the AI to compress without lying. ARCHIVE doesn't — it just moves bytes. When in doubt, MemPenny errs toward ARCHIVE, and you keep the option to come back and DISTILL by hand.

### The dry-run proposal is a ceiling, not a guarantee

The dry-run estimated ~67.8% savings; the apply delivered ~63%. Two reasons:

- A successful MERGE writes one new file (a few hundred bytes), so the post-apply size is slightly higher than the dry-run model.
- DISTILL candidates the safety check can't compress without losing facts get demoted to ARCHIVE. ARCHIVE moves bytes out of auto-load but doesn't shrink the file itself — different math than the dry-run assumed.

Expect a small slippage between the dry-run estimate and the applied result. The direction is always the same (savings); the magnitude can drift by a few percentage points.

## When to expect smaller savings

A clean directory (or a brand-new project) will save less. The ~63% figure here reflects a directory that had been accumulating since the previous pass. Run `/mempenny:clean` on a freshly cleaned dir and the proposal will likely be small or empty — that's the tool telling you nothing meaningful is stale yet, which is also a useful signal.

## Reproducing this run on your own dir

```
/mempenny:clean
```

The first run in any memory directory asks where to keep backups; subsequent runs reuse that folder. Pass `--yes` to skip the confirm gate (this is what `/mempenny:nap` fires on schedule). Everything is backup-first; reverse via `/mempenny:restore` if you don't like a change.
