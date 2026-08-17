---
description: Content-preserving fallback split for an over-ceiling topic file that has no other applicable reduction path — charter.md/pending.md (curate-exempt by design) or a log-topic whose over-ceiling bulk is entirely the still-open period that shard-roll deliberately never touches. Over ceiling → the main file becomes an INDEX and its items become PAGES the index points at.
argument-hint: <path-to-topic-file>
---

Split an over-ceiling topic file that has **no other automated reduction path**. This is the gap `/mempenny:memory-curate` and `/mempenny:memory-shard-roll` leave open (`docs/memory-taxonomy-design.md` §2-§4b): curate never touches `charter.md`/`pending.md` (no `###` entries, and distilling requirements or in-flight work is destructive — correctly so), and shard-roll never touches a year that hasn't fully closed ("no mid-year shards, ever" is shard-roll's own, deliberate pin). Before this command existed, an over-ceiling `pending.md` (or a log-topic stuck entirely in the open year) had **no automatic reduction path at all** and just grew forever until a human noticed — see `docs/memory-taxonomy-design.md`'s §4b for the incident that motivated this.

**The unifying principle: over ceiling → the main file becomes an INDEX, and the items it used to hold become PAGES the index points at.** Three strategies below are three expressions of that one rule, chosen mechanically from what the file actually contains — never guessed, never an LLM judgment call — plus one last-resort fallback for content with no structure to index at all:

1. **DATE** (worklog/support/decisions) — the chronological expression. The parent's own `## Shards` index block (Step 6, below) IS the index; the locked per-period shard files ARE the pages.
2. **SUBJECT-INDEX** (charter/pending, when `## `-structured — the primary, real shape of a working `pending.md`) — the subject expression, and the most direct one: the live file itself becomes the index outright (frontmatter + preamble + one bullet per subject), and every top-level `## ` block becomes its own detail page.
3. **PROSE-PEEL** (charter/pending, only when neither of the above applies) — a last-resort positional split for genuinely structureless prose that still carries datestamps, no index/pages framing, just oldest-vs-newest.
4. **Refuse closed** — nothing to safely index, peel, or order; reported for manual trimming.

Unlike curate, this command makes **no judgment call about content** — it never decides what's worth keeping. It is pure, mechanical, content-preserving relocation. That is what makes it safe to run unattended, even on `pending.md`: nothing is distilled, archived-by-verdict, or deleted — every byte that leaves the live file is proven to still exist, verbatim, somewhere in the pages.

## Step 1 — Parse arguments

The user invoked this command with: $ARGUMENTS

- **First positional argument** — absolute path to a topic file. Required.
- **`--lang <code>`** — output language. Default from `MEMPENNY_LOCALE` or `en`.

There is no `--yes` flag and no confirmation gate — see "Why no confirmation gate" under Constraints below; this matches `/mempenny:memory-shard-roll`, not `/mempenny:memory-curate`.

## Step 2 — Load locale strings

Same 2a validation + read pattern as `memory-distill.md` Step 2. You need `apply.*` and `errors.*` keys. (Like curate/shard-roll at initial release, this command's own report templates are still hardcoded English — tracked as the same follow-up noted in `docs/memory-taxonomy-design.md`, not blocking.)

## Step 3 — Validate the input file path

Identical validation chain to `memory-curate.md` Step 3 (regex, symlink pre-check, realpath, regex re-check, confinement to `{MEMORY_DIR}`, existence), with a different reserved-topic check:

**Reserved-topic check:** the basename must be exactly one of the **5 auto-split-eligible files** — `charter.md`, `pending.md`, `worklog.md`, `support.md`, `decisions.md`. These are precisely the files with no other automated path when over-ceiling (§2-§4b of the design doc). If the target is `traps.md`, `rules.md`, `reference.md`, or a named sub-topic split of one of those, print an error pointing at `/mempenny:memory-curate` instead and STOP — that per-entry judgment is strictly better than a mechanical split whenever it applies. If the target is a `-YYYY.md` / `-YYYY-MM.md` / `-YYYY-MM-DD.md` shard, or a SUBJECT-INDEX detail page (`-NN[-slug].md`), it's either already locked (DATE/PROSE-PEEL pages) or simply not one of the 5 reserved basenames — either way this check already excludes it.

**Folder-lock and file-lock checks:** identical to `memory-curate.md` Step 3. If the target file itself is already locked, STOP — same reasoning as shard-roll: a locked file is either already a closed page or explicitly frozen by the user.

## Step 4 — Back up before any write

Reuse the identical backup machinery as `memory-apply.md`'s "CRITICAL pre-step: backup" — full `cp -a` of `{MEMORY_DIR}`, verified file count, SHA256 manifest, `.memory_layout_at_backup` marker (will record `"topics"`, since auto-split only ever runs on an already-migrated directory). Re-check folder and file locks immediately before backup (TOCTOU close).

## Step 5 — Run the deterministic split script

**Do not perform the split/verify/commit sequence in this (the orchestrating) context, and do not spawn a subagent for it either.** Run this exact command via Bash directly:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/auto-split.sh" "{MEMORY_DIR}" "{basename}" "{TOPIC_TYPE}" 25600 200
```

- `{basename}` — the target file's basename (e.g. `pending.md`).
- `{TOPIC_TYPE}` — the basename without its `.md` extension (e.g. `pending`) — goes in each DATE/PROSE-PEEL page's frontmatter `type:` field (SUBJECT-INDEX pages use a different frontmatter shape, see below), matching shard-roll's own convention.
- `25600` / `200` — the two ceiling constants (25 KB / 200 lines, whichever binds first), identical to `docs/memory-taxonomy-design.md` §2 and `clean.md` Steps 12b/12c's own check. Not parameterized elsewhere in this command; if the design-doc ceiling ever changes, update all three call sites together.

**Why direct, not an isolated subagent (unlike curate/shard-roll's older pattern):** `hooks/auto-split.sh` is a real script FILE, not a large block of inline prompt text a model could be tempted to "help" by retyping — the same reasoning that already justifies `hooks/migrate-move.sh`'s direct invocation in `clean.md` Step 4b.2 step 8 ("no isolation needed — it carries no judgment, only path-validated byte copies"). There is no classification step here at all (unlike curate) and no caller-supplied "which periods to roll" list to isolate (unlike shard-roll, where isolation is described as the command's *only* safety rail beyond the script itself) — the script self-determines everything, including WHICH of the 4 strategies applies, from the two ceiling numbers alone. Its own arguments are paths and integers, never file content; content never flows through this step's prompt.

The script prints exactly one of three shapes to stdout:

- `SPLIT OK: nothing to split (...)` + exit 0 — the file is already at-or-under ceiling, or has no older/further content to peel or index. No write happened. Skip to Step 7 with this outcome.
- `SPLIT FAILED: <reason>` + exit 1 — refused before writing anything (bad args, a lock, a collision, an unbalanced/unresolvable fence, an undeterminable direction) or rolled back cleanly after a conservation-check failure. Skip to Step 7 with this outcome; the backup is the recovery path (`/mempenny:restore`).
- `SCRIPT_OK` + `GRANULARITY=<day|month|subject-index|prose-peel>` + (`PROSE_DIRECTION=<newest-first|newest-last>` if `prose-peel`, or `SUBJECTS_SPLIT=<N>` if `subject-index`) + `SHARD_FILES_WRITTEN: <list>` + `TOTAL_MISSING=0` + `BEFORE_BYTES=`/`AFTER_BYTES=`/`AFTER_LINES=` — a real split happened, committed, and passed its conservation check. Continue to Step 6.

Relay the script's own reported numbers verbatim in Step 7 — do not recompute or re-derive them.

## Step 6 — Update the parent's index (DATE only — SUBJECT-INDEX and PROSE-PEEL need nothing here)

**Skipped entirely if Step 5 returned `SPLIT OK: nothing to split` or `SPLIT FAILED`.** Which half of "index maintenance" belongs to this script vs. this step differs by strategy, on purpose:

- **`GRANULARITY=day` or `month` (DATE):** `hooks/auto-split.sh` deliberately never writes a `## Shards` block itself — same split of responsibility as shard-roll (its own Step 7 script doesn't touch the index either; that's shard-roll.md's separate Step 8). Read the now-split `{basename}`. Find or create a `## Shards` block, immediately after the frontmatter and before the first `## YYYY-MM`/`## YYYY-MM-DD` heading:

  ```
  ## Shards

  - [<page-file>.md](<page-file>.md) — <period> (<N> lines)
  ```

  One line per page **this run** created (from the script's own `SHARD_FILES_WRITTEN` list). If a `## Shards` block already exists (from a prior shard-roll or auto-split run on this file), **preserve its existing lines unchanged and only append this run's new one(s)** — identical discipline to `memory-shard-roll.md` Step 8. Do not re-derive lines for pages this run did not create.

- **`GRANULARITY=subject-index`:** nothing to do here. The script already wrote the complete index directly as the live file's own content — per the unifying principle, **the index IS the main document's job**, not an add-on block within it. Every subject, old and new, already has exactly one bullet, in original order, pointing at its page. There is no separate index section to locate or update; re-reading and re-editing the file here would only risk disturbing what the script already got right.

- **`GRANULARITY=prose-peel`:** nothing to do here either — this strategy doesn't build an index at all (see its own section below for why).

## Step 7 — Report

**On a real split (`SCRIPT_OK`):**

```
AUTO-SPLIT: <topic-file>

Granularity: <day|month|subject-index|prose-peel>
Page(s) written: <SHARD_FILES_WRITTEN from the script, verbatim>

<topic-file>: <BEFORE_BYTES> B -> <AFTER_BYTES> B (<AFTER_LINES> lines)

BACKUP: <path> (<N> files, verified)
```

**On `SPLIT OK: nothing to split`:** relay the script's own message plainly — this is a successful, expected outcome (idempotent re-run, or a file with nothing older/further to index), not a failure.

**On `SPLIT FAILED`:** report the reason, the backup path, and note that the target file was left untouched (a pre-write refusal) or restored (a conservation-check rollback) — either way, nothing needs manual recovery beyond investigating why. Point at `/mempenny:restore` if the user wants to double-check nothing changed.

## SUBJECT-INDEX — the primary strategy for a real pending.md

Verified against the real motivating file (`/home/paniza/.claude/projects/-mnt-data-game3/memory/pending.md`): YAML frontmatter, a short preamble, then dozens of top-level `## ` subject blocks (e.g. `## 🟢 2026-08-10 — SECRET REGISTRY BUILT + VERIFIED (docs/SECRET-REGISTRY.md)`), newest at the top, some carrying nested `### ` detail, some containing fenced code. Applies whenever DATE didn't already claim the file and the file has **≥2 top-level `## ` blocks** (fence-aware — a heading-shaped line quoted inside a fenced example is never mistaken for a real one, same discipline as everywhere else in mempenny), or exactly 1 block immediately following an already-established index from a prior run (see "Incremental re-split," below).

**Unit:** one top-level `## ` block — heading line through the line before the next fence-aware `## ` (or EOF, or the start of an already-existing index — see below). `### ` never becomes its own split unit; it structurally can't be, since `^## ` (exactly two hashes then a space) can never match a `### ` line (whose third character is `#`, not a space) — no extra logic needed to keep nested detail with its parent.

**Detail pages:** each block becomes its own file `<topic>-<NN>-<slug>.md`.
- `NN` — zero-padded ordinal, continuing from whatever the highest existing `<topic>-NN...md` on disk already is (0 on a first-ever split), assigned to this run's blocks in top-to-bottom (newest-to-oldest) file order. Continuing rather than restarting at 01 on every run is what makes numbering collision-free across repeated splits over the file's life — see "Incremental re-split" below for why restarting would be unsafe.
- `slug` — kebab-cased from the heading text: a `YYYY-MM-DD` date token is stripped first (so its hyphens aren't mistaken for word separators), then everything that isn't an ASCII letter/digit/space is stripped (this also correctly and safely removes emoji — every byte of a multi-byte UTF-8 character falls outside `A-Za-z0-9`, so the whole character is cleanly deleted, never left mangled), lowercased, spaces become hyphens, truncated to ~40 characters. **A slug that strips to empty** (an emoji-and-date-only heading with no describing words) **falls back to `<topic>-<NN>.md` alone** — never a dangling hyphen or an empty component. The final filename is always validated against the same H1 filename regex as every other mempenny-generated name.
- **Collision fallback:** if the computed candidate already exists on disk (from some other source — NN uniqueness makes a collision within the same run's own batch structurally impossible), append `-2`, `-3`, … to the whole stem until it doesn't. Deterministic, same "never overwrite, always resolve predictably" precedent as everywhere else.
- **Frontmatter:** `name: <file stem>`, `description: "<heading text, sans the leading '## ', YAML-escaped>"`, `metadata:\n  type: <TOPIC_TYPE>` — the same `name`/`description`/`metadata.type` shape MemPenny's own migration-era MERGE-WRITE content already used for individual reference-style files, not a new convention. Body: the block **verbatim**, starting with its original `## ` heading line.
- **Deliberately left UNLOCKED — a feature, not an oversight.** DATE and PROSE-PEEL pages are frozen because they represent genuinely closed history. A SUBJECT-INDEX page represents one in-flight subject that may resolve later — leaving it unlocked means `/mempenny:memory-curate` (or a future nap run) can finally archive or delete a `🟢`-then-resolved or `🟧`-superseded subject once it's done, which `pending.md`'s own blanket curate-exemption previously made impossible for as long as that subject lived inside the monolithic file. Splitting a subject out doesn't just shrink the file — it makes the subject triage-able for the first time.

**The live file becomes the index, full stop — not "gets an index section added."** Per the unifying principle, this is the main document's whole job now: frontmatter + preamble (unchanged, verbatim) + one bullet per subject, in original (file) order:

```
- [<heading text verbatim, sans "## ", `[`/`]` escaped for valid markdown link syntax>](<page-file>.md)
```

A clean, scannable map — every subject, one line, nothing else. Zero `## ` headings survive in the live file once fully split; they've all become link targets.

**MEMORY.md does not balloon.** The (potentially dozens of) detail pages are never added to `MEMORY.md` — the live `pending.md` IS the pointer layer for its own subjects; `MEMORY.md` keeps its single, unchanged `pending.md` line, same as always.

**Incremental re-split — only new subjects split, existing pages never touched.** Once a block is converted, it has no `## ` heading left at all (just a bullet) — so a later scan's fence-aware `## ` detection structurally cannot rediscover it as "still needing a split," with no separate "is this already done" check required. When new subjects are later prepended above an existing index and the file crosses the ceiling again: the script detects where the newest of *this run's* raw blocks ends and the old, already-collapsed index begins (the first line after it matching the index-bullet shape), treats that trailing region as verbatim passthrough exactly like preamble, and converts only the genuinely new blocks. New bullets are inserted first (preserving newest-first order); every old bullet, and every old page file, survives byte-for-byte untouched. This is also why NN must continue rather than restart per run — restarting at 01 on a later split would silently collide with page files an earlier split already wrote.

## PROSE-PEEL — last-resort fallback, direction derived from datestamps

Applies only when neither DATE nor SUBJECT-INDEX applies — a genuinely structureless file (fewer than 2 `## ` blocks, no date-only headings) that still carries datestamps somewhere in its body. There's no subject or period structure to build an index over here, so this strategy doesn't build one — it's a plain positional split, oldest content becomes one page, newest stays live.

An earlier draft of this command hardcoded "head = oldest, tail = newest" (content appended at the end) as an unverified assumption, flagged back as an open question. **Verified against the real motivating file: `pending.md` is actually SUBJECT-INDEX-shaped** (see above) — but the direction question was real, and hardcoding a guess either way would have carried the same fragility for whatever OTHER dated-but-structureless file this fallback ever actually fires on. So `hooks/auto-split.sh` **derives** the direction per file rather than assuming either one:

- Scans the file body (outside frontmatter) for the first and last `YYYY-MM-DD` (or, failing that, `YYYY-MM`) datestamp it can find, in file order.
- **Top date newer than bottom date → newest-first:** the oldest content is the suffix (bottom) — page the suffix, keep the prefix (top) live.
- **Top date older than bottom date → newest-last:** the oldest content is the prefix (top) — page the prefix, keep the suffix (bottom) live.
- **No datestamp anywhere, or only one distinct date (no direction to derive) → fails closed**, reported plainly, rather than guessing. In practice this means a genuinely dateless `charter.md` (the common real shape — goals/requirements prose rarely carries dates, and rarely has ≥2 `## ` blocks either) is refused and left for manual trimming.
- Either direction, the fence-safety nudge always moves toward the PAGE side (never the side staying live) — the ceiling-safe direction, whichever end that happens to be.
- `SCRIPT_OK` output includes `PROSE_DIRECTION=<newest-first|newest-last>` for operator visibility.

Both directions and both fail-closed paths (dateless, single-date) are covered in `tests/run-autosplit.sh`, alongside SUBJECT-INDEX's own realistic fixture, incremental re-split, empty-slug, and collision cases.

## Constraints

- Never touches `traps.md`, `rules.md`, `reference.md`, or their sub-topic splits — those go through `/mempenny:memory-curate`. Never touches an already-locked page from any source.
- DATE never removes the single newest period; PROSE-PEEL never removes the whole file — always leaves at least something live, even when that remainder alone is still over ceiling (reported plainly, not hidden — see the DATE strategy's "floor tolerated" behavior in `hooks/auto-split.sh`'s own header comment). SUBJECT-INDEX has no analogous partial-peel step to begin with — every currently-unindexed block becomes a page in one pass, and the index itself (all bullets, always present) is what stays live.
- A second genuine over-ceiling episode on the same calendar day for a PROSE-PEEL file fails closed on a page-name collision rather than silently overwriting or appending — documented, accepted limitation; resolve manually (rename the existing day's page, or wait for the next day). SUBJECT-INDEX has no equivalent same-day limitation — NN-based naming is collision-free across any number of same-day runs by construction.
- Do not modify files outside `{MEMORY_DIR}`.
- If any step fails after Step 4's backup completes, the backup is the recovery path — point the user at `/mempenny:restore`.

**Why no confirmation gate:** identical justification to `/mempenny:memory-shard-roll` — move-only (verbatim, never distilled/summarized), backed up first, and gated on a conservation check that rolls back on its own if anything doesn't add up. There is no classification step to review (unlike curate's per-entry table), so there is nothing for a human to approve that the conservation check doesn't already prove mechanically. This is also what makes it safe to trigger automatically from `/mempenny:clean` on `pending.md`/`charter.md` without weakening curate's own exemption for those two files in any way — curate still never runs on them; this is a different, orthogonal, lossless operation.

**Relationship to `hooks/shard-roll.sh` (the not-yet-wired v1.5 adaptive engine):** deliberately independent, not built on top of it. `hooks/shard-roll.sh` only recognizes `## YYYY-MM-DD` day headings and is explicitly documented as standalone groundwork ("Not yet wired... connecting the engine to the commands... is the next release" — see `CHANGELOG.md` v1.5.0). `hooks/auto-split.sh`'s DATE strategy recognizes **either** `## YYYY-MM` or `## YYYY-MM-DD` headings (auto-detected per file), which is necessary right now because the currently-*wired* `/mempenny:memory-shard-roll` only understands the month shape while the currently-shipped `hooks/migrate-move.sh` already writes the day shape — a real, pre-existing mismatch this command's own detection has to tolerate regardless of when (or whether) that separate unification lands. Taking a dependency on `hooks/shard-roll.sh` here would have inherited its day-only assumption and silently failed to fire on month-shaped files. Worth a look when the day/month unification work happens — that's a separate, larger effort than this file touches.
