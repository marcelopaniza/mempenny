---
description: Content-preserving fallback split for an over-ceiling topic file that has no other applicable reduction path — charter.md/pending.md (curate-exempt by design) or a log-topic whose over-ceiling bulk is entirely the still-open period that shard-roll deliberately never touches. Moves the OLDEST content verbatim into a shard; the newest/in-flight content stays live.
argument-hint: <path-to-topic-file>
---

Split an over-ceiling topic file that has **no other automated reduction path**, by moving its oldest content verbatim into a shard and leaving the newest/in-flight content live. This is the gap `/mempenny:memory-curate` and `/mempenny:memory-shard-roll` leave open (`docs/memory-taxonomy-design.md` §2-§4): curate never touches `charter.md`/`pending.md` (no `###` entries, and distilling requirements or in-flight work is destructive — correctly so), and shard-roll never touches a year that hasn't fully closed ("no mid-year shards, ever" is shard-roll's own, deliberate pin). Before this command existed, an over-ceiling `pending.md` (or a log-topic stuck entirely in the open year) had **no automatic reduction path at all** and just grew forever until a human noticed — see `docs/memory-taxonomy-design.md`'s "Auto-split (v1.6)" note for the incident that motivated this.

Unlike curate, this command makes **no judgment call about content** — it never decides what's worth keeping. It is pure, mechanical, content-preserving relocation, exactly like shard-roll, just not gated on calendar-year closure. That is what makes it safe to run unattended, even on `pending.md`: nothing is distilled, archived-by-verdict, or deleted — every byte that leaves the live file is proven to still exist, verbatim, in the shard.

## Step 1 — Parse arguments

The user invoked this command with: $ARGUMENTS

- **First positional argument** — absolute path to a topic file. Required.
- **`--lang <code>`** — output language. Default from `MEMPENNY_LOCALE` or `en`.

There is no `--yes` flag and no confirmation gate — see "Why no confirmation gate" under Constraints below; this matches `/mempenny:memory-shard-roll`, not `/mempenny:memory-curate`.

## Step 2 — Load locale strings

Same 2a validation + read pattern as `memory-distill.md` Step 2. You need `apply.*` and `errors.*` keys. (Like curate/shard-roll at initial release, this command's own report templates are still hardcoded English — tracked as the same follow-up noted in `docs/memory-taxonomy-design.md`, not blocking.)

## Step 3 — Validate the input file path

Identical validation chain to `memory-curate.md` Step 3 (regex, symlink pre-check, realpath, regex re-check, confinement to `{MEMORY_DIR}`, existence), with a different reserved-topic check:

**Reserved-topic check:** the basename must be exactly one of the **5 auto-split-eligible files** — `charter.md`, `pending.md`, `worklog.md`, `support.md`, `decisions.md`. These are precisely the files with no other automated path when over-ceiling (§2-§3 of the design doc). If the target is `traps.md`, `rules.md`, `reference.md`, or a named sub-topic split of one of those, print an error pointing at `/mempenny:memory-curate` instead and STOP — that per-entry judgment is strictly better than a position-based split whenever it applies. If the target is a `-YYYY.md` / `-YYYY-MM.md` / `-YYYY-MM-DD.md` shard (from shard-roll or from a prior auto-split run), it will already be locked — the file-lock check below catches it, but the reserved-topic check itself already excludes it by name (a shard's basename is never one of the 5 exactly).

**Folder-lock and file-lock checks:** identical to `memory-curate.md` Step 3. If the target file itself is already locked, STOP — same reasoning as shard-roll: a locked file is either already a closed shard or explicitly frozen by the user.

## Step 4 — Back up before any write

Reuse the identical backup machinery as `memory-apply.md`'s "CRITICAL pre-step: backup" — full `cp -a` of `{MEMORY_DIR}`, verified file count, SHA256 manifest, `.memory_layout_at_backup` marker (will record `"topics"`, since auto-split only ever runs on an already-migrated directory). Re-check folder and file locks immediately before backup (TOCTOU close).

## Step 5 — Run the deterministic split script

**Do not perform the split/verify/commit sequence in this (the orchestrating) context, and do not spawn a subagent for it either.** Run this exact command via Bash directly:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/auto-split.sh" "{MEMORY_DIR}" "{basename}" "{TOPIC_TYPE}" 25600 200
```

- `{basename}` — the target file's basename (e.g. `pending.md`).
- `{TOPIC_TYPE}` — the basename without its `.md` extension (e.g. `pending`) — goes in each shard's frontmatter `type:` field, matching shard-roll's own convention.
- `25600` / `200` — the two ceiling constants (25 KB / 200 lines, whichever binds first), identical to `docs/memory-taxonomy-design.md` §2 and `clean.md` Steps 12b/12c's own check. Not parameterized elsewhere in this command; if the design-doc ceiling ever changes, update all three call sites together.

**Why direct, not an isolated subagent (unlike curate/shard-roll's older pattern):** `hooks/auto-split.sh` is a real script FILE, not a large block of inline prompt text a model could be tempted to "help" by retyping — the same reasoning that already justifies `hooks/migrate-move.sh`'s direct invocation in `clean.md` Step 4b.2 step 8 ("no isolation needed — it carries no judgment, only path-validated byte copies"). There is no classification step here at all (unlike curate) and no caller-supplied "which periods to roll" list to isolate (unlike shard-roll, where isolation is described as the command's *only* safety rail beyond the script itself) — the script self-determines everything from the two ceiling numbers. Its own arguments are paths and integers, never file content; content never flows through this step's prompt.

The script prints exactly one of three shapes to stdout:

- `SPLIT OK: nothing to split (...)` + exit 0 — the file is already at-or-under ceiling, or has no older content to peel (a single period, or nothing outside frontmatter). No write happened. Skip to Step 7 with this outcome.
- `SPLIT FAILED: <reason>` + exit 1 — refused before writing anything (bad args, a lock, a collision, an unbalanced/unresolvable fence) or rolled back cleanly after a conservation-check failure. Skip to Step 7 with this outcome; the backup is the recovery path (`/mempenny:restore`).
- `SCRIPT_OK` + `GRANULARITY=<day|month|prose>` + `SHARD_FILES_WRITTEN: <list>` + `TOTAL_MISSING=0` + `BEFORE_BYTES=`/`AFTER_BYTES=`/`AFTER_LINES=` — a real split happened, committed, and passed its conservation check. Continue to Step 6.

Relay the script's own reported numbers verbatim in Step 7 — do not recompute or re-derive them.

## Step 6 — Update the Shards index (only on `SCRIPT_OK`)

**Skipped entirely if Step 5 returned `SPLIT OK: nothing to split` or `SPLIT FAILED`.** `hooks/auto-split.sh` deliberately never writes a `## Shards` block itself — same split of responsibility as shard-roll (its own Step 7 script doesn't touch the index either; that's shard-roll.md's separate Step 8). Read the now-split `{basename}`. Find or create a `## Shards` block, immediately after the frontmatter and before the first line of real content (the first `## YYYY-MM`/`## YYYY-MM-DD` heading for the DATE strategy, or the first content line for the PROSE strategy):

```
## Shards

- [<shard-file>.md](<shard-file>.md) — <one-line description>
```

One line per shard **this run** created (from the script's own `SHARD_FILES_WRITTEN` list) — for the DATE strategy, `<period> (<N> lines)`; for the PROSE strategy, `<N> lines archived <run-date>`. If a `## Shards` block already exists (from a prior shard-roll or auto-split run on this file), **preserve its existing lines unchanged and only append this run's new one(s)** — identical discipline to `memory-shard-roll.md` Step 8. Do not re-derive lines for shards this run did not create.

## Step 7 — Report

**On a real split (`SCRIPT_OK`):**

```
AUTO-SPLIT: <topic-file>

Granularity: <day|month|prose>
Shard(s) written: <SHARD_FILES_WRITTEN from the script, verbatim>

<topic-file>: <BEFORE_BYTES> B -> <AFTER_BYTES> B (<AFTER_LINES> lines)

BACKUP: <path> (<N> files, verified)
```

**On `SPLIT OK: nothing to split`:** relay the script's own message plainly — this is a successful, expected outcome (idempotent re-run, or a file with nothing older to peel), not a failure.

**On `SPLIT FAILED`:** report the reason, the backup path, and note that the target file was left untouched (a pre-write refusal) or restored (a conservation-check rollback) — either way, nothing needs manual recovery beyond investigating why. Point at `/mempenny:restore` if the user wants to double-check nothing changed.

## Constraints

- Never touches `traps.md`, `rules.md`, `reference.md`, or their sub-topic splits — those go through `/mempenny:memory-curate`. Never touches an already-locked shard from any source.
- Never removes the single newest period (DATE strategy) or the whole file (PROSE strategy) — always leaves at least something live, even when that remainder alone is still over ceiling (reported plainly, not hidden — see the DATE strategy's "floor tolerated" behavior in `hooks/auto-split.sh`'s own header comment).
- A second genuine over-ceiling episode on the same calendar day for a PROSE-strategy file (`pending.md`/`charter.md`) fails closed on a shard-name collision rather than silently overwriting or appending — documented, accepted limitation; resolve manually (rename the existing day's archive shard, or wait for the next day).
- Do not modify files outside `{MEMORY_DIR}`.
- If any step fails after Step 4's backup completes, the backup is the recovery path — point the user at `/mempenny:restore`.

**Why no confirmation gate:** identical justification to `/mempenny:memory-shard-roll` — move-only (verbatim, never distilled/summarized), backed up first, and gated on a conservation check that rolls back on its own if anything doesn't add up. There is no classification step to review (unlike curate's per-entry table), so there is nothing for a human to approve that the conservation check doesn't already prove mechanically. This is also what makes it safe to trigger automatically from `/mempenny:clean` on `pending.md`/`charter.md` without weakening curate's own exemption for those two files in any way — curate still never runs on them; this is a different, orthogonal, lossless operation.

**Relationship to `hooks/shard-roll.sh` (the not-yet-wired v1.5 adaptive engine):** deliberately independent, not built on top of it. `hooks/shard-roll.sh` only recognizes `## YYYY-MM-DD` day headings and is explicitly documented as standalone groundwork ("Not yet wired... connecting the engine to the commands... is the next release" — see `CHANGELOG.md` v1.5.0). `hooks/auto-split.sh` recognizes **either** `## YYYY-MM` or `## YYYY-MM-DD` headings (auto-detected per file), which is necessary right now because the currently-*wired* `/mempenny:memory-shard-roll` only understands the month shape while the currently-shipped `hooks/migrate-move.sh` already writes the day shape — a real, pre-existing mismatch this command's own detection has to tolerate regardless of when (or whether) that separate unification lands. Taking a dependency on `hooks/shard-roll.sh` here would have inherited its day-only assumption and silently failed to fire on month-shaped files. Worth a look when the day/month unification work happens — that's a separate, larger effort than this file touches.

## Open design question for Marcelo

**The PROSE strategy's "oldest = head, newest = tail" assumption has no documented basis to verify against — it's the one real judgment call in an otherwise fully mechanical design, and I couldn't confirm it empirically without opening a real memory directory (out of scope for this task by your own instruction).** `docs/memory-taxonomy-design.md` §3 says only "plain prose, no structure" for `charter.md`/`pending.md` — there's no stated append-direction convention (unlike worklog/support's explicit "newest month first, newest entry first"). I chose **head = oldest, tail = newest** (content-appended-at-the-end), on the reasoning that this is the near-universal convention for a running notes/pending-items file, and getting it backwards would be the worse failure mode (silently shredding the newest in-flight work instead of the oldest). This assumption is isolated to one clearly-commented block in `hooks/auto-split.sh`'s PROSE strategy — if you know real `pending.md` files grow the other way (or don't consistently grow in either direction), that block is the only place to change, and the fixture tests in `tests/run-autosplit.sh` would need their tail/head assertions flipped to match.
