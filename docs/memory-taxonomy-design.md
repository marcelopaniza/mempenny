# Memory Taxonomy & Auto-Migration — Design Spec

Status: implemented and reviewed, 2026-07-02, released as v1.1.0. All pieces below shipped: config schema (`memory_layout`/`migrate_documents`), the topic-scaffold rubric guard (filename + `type:` frontmatter gated), auto-migration (`clean.md` Step 4b, isolated apply subagent, scripted conservation check), restore/marker sync, `/mempenny:memory-curate` (traps/rules/reference only), and `/mempenny:memory-shard-roll` (isolated apply subagent, pre-flight collision check). This project's own memory dir was migrated as the first real-world run (see `worklog.md` in the memory dir for the record). Pre-deploy review completed: code-review + pentest (Sonnet) + Fable (standing in for gemini, which is currently unavailable — account tier deprecated) all ran against the full diff; 4 corroborated critical findings and several moderates were fixed before this status line was updated. Not yet done: full i18n for `/mempenny:memory-curate` and `/mempenny:memory-shard-roll`'s own output (locale keys are loaded but the report templates are still hardcoded English) — tracked as a follow-up, not blocking.

## Background

MemPenny's current auto-memory layout is one flat MEMORY.md index per project, pointing at individually-typed .md files (user/feedback/project/reference). This spec replaces it with a fixed, 3-level topic taxonomy, plus an automated migration path so every project converts to it without manual work.

## 1. The 8 topic files

| File | Purpose |
|---|---|
| charter.md | Goal + requirements for the artifact — small, stable, merged because always read together. |
| pending.md | In-flight work; volatile, overwritten freely; never sharded. |
| worklog.md | Datestamped log of completed/shipped changes to the artifact. |
| support.md | One log of helping people/systems operate the artifact; ages out by calendar, never "migrates" between files. |
| traps.md | Discovered hazards: condition + consequence + how to avoid. |
| rules.md | Standing directives for the workers — rituals, approvals, escalation. |
| decisions.md | ADR-style: why X over Y, alternatives rejected. |
| reference.md | Who/what-is-X: people, systems, URLs, invocation strings. |

Optional `howto.md` only if a procedure has no other home; it's the only permitted 9th MEMORY.md line, and migration never creates it.

**Disambiguators:**
- Requirement vs. rule: constrains the artifact vs. constrains the workers.
- Trap vs. rule: discovered hazard with a condition vs. directive without context. A trap promoted to a rule lives only in rules.md and may cite the trap.
- Worklog vs. support: changed the artifact vs. helped someone operate it.

**Canonical-home relaxation:** no requirement that an item have exactly one home. The same thing linked/mentioned from multiple topic files is expected, not a defect. Cross-references use `[[name]]`, targeting a heading's slug — link targets are `###` headings (traps, rules, reference entities, decisions) and topic filenames. Worklog/support list items are not link targets, by design.

## 2. Sharding rule

Only log-topics shard: worklog, support, decisions. Reference-topics (charter, rules, traps, reference, pending) never time-shard — over the ceiling they're reduced in place via **curate** (§4), or split by named sub-topic (e.g. `rules-prod.md`) as a deliberate human decision if genuinely irreducible.

- **Trigger:** 25KB or 200 lines, whichever first (matches Claude Code's own eager-load ceiling). Entry count (~50) is a review trigger, not a split trigger.
- **Mechanism:** a closed calendar year becomes `topic-YYYY.md`, flat, no subfolders, with the existing `mempenny-lock` marker on line 1 as the freeze mechanism (reuses shipped lock surface, zero new code for the freeze itself).
- **Index:** MEMORY.md only ever lists the 8 topic names — it never grows. Each sharded topic carries its own `## Shards` block (and `## Sub-files` block if a sub-topic split exists) at the top of the file, after any lock/title line, before the newest month. Sub-files (`rules-prod.md`, `howto.md`) are indexed there, never in MEMORY.md.
- **Pin:** shard-roll fires only at closed-year granularity. An open year that alone exceeds the ceiling is flagged in clean's report and tolerated — no mid-year shards, ever.
- Worst case for a cold agent: 3 deterministic file-opens to find anything.

## 3. Internal entry conventions

- **Log-topics** (worklog, support, decisions): entries grouped under lazily-created `## YYYY-MM` headings inside the current file (open `topic.md` or a closed `topic-YYYY.md` shard) — newest month first, newest entry first, never pre-create empty months.
  - worklog/support: `- **YYYY-MM-DD** — summary.` + optional 1-2 sentences. No other required fields.
  - decisions: `### YYYY-MM-DD — <greppable title>` (e.g. "nap non-interactive by design"), body beneath. Headings, not list items — this is what makes them linkable via `[[name]]` and lookup-by-topic rather than only by date.
- **traps.md / rules.md:** each entry is `### <short name>` containing the existing rule → **Why:** → **How to apply:** shape already used for today's individual feedback memories — reused, not reinvented.
- **reference.md:** `### <entity name>` + loose free-form lines (what it is, where/how to reach it). No rigid template — entity types vary too much for one shape to fit all.
- **charter.md / pending.md:** plain prose, no structure. Exempt from all automated reduction (no auto-curate, no auto-distill — distilling requirements is destructive). Over-ceiling is only flagged for human attention.

## 4. The "curate" operation (new capability)

Per-entry curation for over-ceiling reference-topics. Distinct from `memory-distill`, which is file-granularity and would be destructive on a multi-entry file (collapsing 15 independent rules into 3 sentences). Curate walks a file's individual `###` entries and applies memory-hygiene's existing keep/archive/delete judgment per entry — one heading = one decision.

- Runs through the same propose-table → apply-with-backup pipeline as triage/apply (unattended under nap's `--yes`, same as everything else — no special-casing).
- Entry-level ARCHIVE reuses the existing archive-destination convention at entry granularity.
- Skips locked files, per existing lock semantics.
- Triggered when clean finds a reference-topic over the ceiling.

## 5. Migration / auto-conversion design

**Config additions** to `~/.claude/mempenny.config.json` (v2 schema), per memory dir — see `commands/clean.md` Step 4 for the authoritative schema doc and validation rules:

- **`memory_layout`** — `"flat"` (default/absent — not yet migrated) or `"topics"` (migration complete). Explicit detection marker, never inferred from filenames present. Written only after a successful migration's conservation check passes; re-synced by `/mempenny:restore` to match whatever layout it actually restored.
- **`migrate_documents`** — boolean, default `true` when absent. Set `false` for a memory dir to opt it out of auto-migration permanently. Sits above the existing per-directory `.mempenny-lock`: the lock blocks migration for one run, this flag blocks it until a human flips it back.

**Classification:** a read-only subagent (`subagent_type: Explore` — same structurally-can't-write pattern as triage) reads every file in the old flat layout and proposes a migration table: old file/content → target new topic file + section.

**Move-only vocabulary (binding):** the migration table's only verb is *relocate verbatim*. No delete, no rewrite, no summarizing. A source file may split into multiple entries at heading/bullet boundaries; each old file's content defaults to landing under a `###` heading named from its filename stem (preserves provenance, gives it a stable link target). Unplaceable content goes verbatim under `## Unsorted (migrated YYYY-MM-DD)` in reference.md rather than being dropped or guessed at. Dedup/merge/tidy is curate's job later, through the reviewed pipeline — migration never does it.

**Apply:** reuses the existing backup → verified file count → SHA256-manifest-before-any-destructive-action → restore machinery verbatim.

**No confirmation gate** — ratified by Fable, conditional on:
- **Move-only** (above) — worst case is misfiled content, never lost content.
- **Conservation check:** after writing the new layout and before removing anything old, mechanically verify every normalized non-empty line of every old file (including old MEMORY.md's own per-file summary bullets, which are real content) appears somewhere in the new layout. Fail → auto-restore, `memory_layout` marker left unset, loud visible error. Marker written last, only after verification passes (crash-safe: a half-run re-detects the old layout next time and the restore covers the rest).
- **Post-migration report, always:** N files → 8 topics, placement summary, explicit backup path, one-line restore command. No gate *before*; full transparency *after* — this is what preserves informed awareness without relying on an uninformed rubber-stamp.
- **Any lock aborts migration entirely** (folder-level `.mempenny-lock`/`.mempenny-fixture`, or a file-level `mempenny-lock` comment anywhere in the dir) — report why, don't attempt a partial/mixed-layout migration.

**Trigger scoping:**
- Only `clean` (including nap → clean) performs migration writes. `triage` stays read-only and reports "old layout — will migrate on next clean." `restore` never migrates.
- A migrating run is exclusive: migrate, report, stop. Triage/clean-proper happens on the *next* run — one structural change per unattended run.
- If the backup folder isn't configured yet for this dir, the existing first-run backup-folder prompt still runs first (configuration, not a consent gate on the migration itself).
- Empty or never-touched memory dirs skip classification entirely and are scaffolded directly: all 8 files created with a one-line purpose header each, so the fixed index is always truthful from the start.
- **Restore/marker sync:** backup manifests record `memory_layout` at backup time; restore sets the dir's marker to match what it restored, so restoring a pre-migration backup doesn't leave the marker permanently lying about the layout.

**Build-order constraint (blocking, not follow-on work):** the topic-aware triage/clean rubric — never DELETE or DISTILL an empty/near-empty scaffold topic file; cluster analysis stays within same-topic boundaries — must ship *before or with* auto-migration. Without it, the first post-migration nap-triggered clean sees 8 mostly-empty scaffolds and could delete them under today's rubric, destroying the very structure that was just built.

## Implementation notes

- Apply must fail-safe when a table references files that no longer exist (e.g. a pre-migration triage table applied post-migration): refuse, demand re-triage, never partially apply.
- No new concurrency guarantees — same single-session assumption as existing clean.
- `/mempenny:memory-curate` and `/mempenny:memory-shard-roll` are standalone commands, triggered automatically by `/mempenny:clean` Steps 12b/12c when a topic file crosses the ceiling, but also directly invocable by a user against any topic file.
- A pre-existing, unrelated bug was found and fixed during this implementation: the C1 path-validation regex (`^/[A-Za-z0-9/_.\- ]{1,4096}$`) and the L2 glob regex were malformed POSIX bracket expressions that never matched anything when executed literally via `grep -E`/bash `[[ =~ ]]` — most seriously in `hooks/nap-check.sh`, where it silently caused the SessionStart hook to exit before ever checking a nap schedule. Fixed everywhere by repositioning `-` to the end of each character class and moving `]` to the front where it needs to be literal. This means `/mempenny:nap` may never have actually fired for any user before this fix.
