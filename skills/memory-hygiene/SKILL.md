---
name: memory-hygiene
description: Load this skill when the user asks how to write, prune, or manage their Claude Code auto-memory files. Covers the strategy hierarchy (delete > archive > distill > compress > keep), recognition heuristics for stale memories, the forward-looking-truth principle, and write-time discipline.
---

# Memory Hygiene

Claude Code's auto-memory system is powerful but can rot. Files accumulate across sessions, and the cost of a bloated memory directory is paid on **every** new conversation. This skill covers how to write memories that don't rot, and how to prune the ones that already did.

## The strategy hierarchy

Cheapest action to most expensive. Always pick the cheapest one that applies.

1. **DELETE** — zero tokens, zero loss if the content is truly obsolete. Use when:
   - The fix is now in the code (code is authoritative, memory can lie)
   - One-shot resolved bug or incident with no future implication
   - Explicitly marked "RESOLVED" / "do not re-fix" / "Historical only"
   - Superseded by a newer file on the same topic

2. **ARCHIVE** — move to `archive/` subdir, remove from `MEMORY.md` index. The file still exists for forensics if future debugging needs it, but it's out of the auto-load path. Use for completed-but-non-trivial incidents where the story matters, but not for daily lookup.

3. **DISTILL** — replace prose narrative with 1-3 sentences of forward-looking truth. The narrative gets dropped; only what future-Claude needs to know remains. This is the most common action on aging memory files.

4. **COMPRESS** — out of scope for memory-hygiene. This is [caveman](https://github.com/JuliusBrussee/caveman)'s job. Compression runs on prose that's already been through the triage above — it shrinks what's left, but doesn't decide what should be there. Run MemPenny first, then compress survivors if you want additional savings.

5. **KEEP** — active state, architecture reference, recurring rule, or content where the prose is already tight. The default action when none of the above apply.

## Recognition heuristics

When you're looking at a memory file and deciding its fate:

- **Dated `YYYYMMDD` files** documenting a one-day incident → usually DISTILL or ARCHIVE. The date in the filename is a strong signal that it's a snapshot that's aging.
- **Files containing "RESOLVED", "verified clean", "fixed in", "do not re-fix"** → likely DELETE or ARCHIVE. The file is telling you its own lifecycle is over.
- **Architecture / service / protocol / reference docs** → KEEP. These are the stable substrate.
- **Single test-run results** → DISTILL to "what's now true" after that test run.
- **Files >5 KB with narrative prose** → DISTILL aggressively. Narrative is almost never load-bearing for future-Claude.
- **Small stable reference files** (usually under 2 KB) → KEEP. Low cost, high density.

## The forward-looking-truth principle

**Memory captures what future-Claude needs to know, not what past-Claude experienced.**

- Narrative "what happened" is git-log territory. Don't duplicate it in memory.
- Fixes that are now in the code are authoritative from the code. Memory that repeats them will eventually disagree and mislead.
- The load-bearing part of any postmortem is almost always 1-3 sentences. If you can't find it, the memory is probably all narrative.

**Test:** "If I read this file in three weeks with no other context, what's the one thing I need it to tell me?" That one thing is the memory. Everything else is bloat.

## Write-time discipline

The best memories are born lean. Five rules:

1. **Search before writing** — if a relevant memory already exists, update it instead of creating a new one. Duplicate memories are the biggest source of rot.
2. **Distill as you write** — don't plan to "clean up later". Write the forward-looking sentence first, then stop. The narrative you'd be tempted to add is in git.
3. **Include the "why" in feedback memories** — so future edge cases can be judged, not just blindly followed. A rule without a reason becomes brittle.
4. **Delete in the same session you learn something is obsolete** — the moment you notice a memory is stale, kill it. Dead memories accumulate if you defer.
5. **Make `MEMORY.md` descriptions specific** — vague descriptions ("various fixes") cause unnecessary loads. Specific descriptions ("retry policy: exponential backoff, max 5, gives up on 4xx") let future-Claude filter more accurately.

## The overall principle

> **"Save tokens with common sense, without loss."**

Lean memory isn't about being aggressive — it's about being honest about what's load-bearing. A 10 KB file with two load-bearing sentences should become a 2-sentence file. A 10 KB file where every line is load-bearing should stay exactly as it is.

The judgment call is always: **does future-Claude need the narrative, or just the conclusion?**

The conclusion is what matters 99% of the time. Narrative lives in git.

## When in doubt

When in doubt, favor ARCHIVE over DELETE. ARCHIVE is reversible (move back out of `archive/`), DELETE is not (unless there's a backup). The goal is "without loss", not "maximum savings at any cost".
