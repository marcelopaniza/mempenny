---
description: Dry-run triage of a Claude Code auto-memory directory. Produces a markdown table of proposed actions (delete / archive / distill / keep). No writes.
argument-hint: [--dir <path>] [--only <glob>] [--lang <code>]
---

Triage an auto-memory directory as a **read-only dry run**. No file modifications.

## Step 1 — Parse arguments

The user invoked this command with: $ARGUMENTS

Parse three optional arguments from `$ARGUMENTS`:

- `--dir <path>` — absolute path to the memory directory to triage. If set, use it verbatim and skip auto-detection. If not set, auto-detect the current project's memory dir (see Step 3). This is the escape hatch for triaging another project's memory without switching sessions.
- `--only <glob>` — scope filter (e.g., `--only project_*.md` or `--only "project_*_20*.md,reference_*.md"`). Default: every `.md` file directly under the memory dir.
- `--lang <code>` — output language for distilled replacements and summary labels (e.g., `--lang pt-BR`). If not passed, check the `MEMPENNY_LOCALE` environment variable. If that's also unset, default to `en`.

## Step 2 — Load locale strings

Read `${CLAUDE_PLUGIN_ROOT}/locales/<lang>/strings.json` using the Read tool. If the file does not exist, fall back to `${CLAUDE_PLUGIN_ROOT}/locales/en/strings.json` and warn the user with the `errors.locale_missing` message (filling in `{lang}` with the requested code).

Keep the loaded JSON in working memory — you'll need `triage.*` labels for the final summary and `distill_output_instruction` for the subagent prompt.

## Step 3 — Locate the memory directory

**If `--dir <path>` was passed in Step 1**, use that path verbatim as `{MEMORY_DIR}`. Verify the directory exists and contains at least one `.md` file before continuing. Skip the rest of this step.

**Otherwise**, auto-detect: the auto-memory directory for the current project is at `~/.claude/projects/<project-id>/memory/`. Detect `<project-id>` from the current working directory's mapping. If you cannot determine it unambiguously, ask the user for the absolute path to their memory directory (use `errors.memory_dir_not_found` as the error template).

## Step 4 — Determine scope

**Default scope:** every `.md` file directly under the memory directory, excluding `MEMORY.md`, any `*.original.md` backup files, and anything under `archive/`.

If `--only <glob>` was provided, narrow to that pattern. Multiple globs can be comma-separated.

## Step 5 — Spawn the triage subagent

Use the Agent tool with these parameters:

- `subagent_type: Explore` (read-only, safer for a dry run)
- `model: sonnet` (mechanical classification — no need for Opus)
- `run_in_background: false`
- `prompt`: the triage prompt below, parameterized with `{MEMORY_DIR}`, `{SCOPE_GLOB}`, and `{DISTILL_OUTPUT_INSTRUCTION}` (which is `locale.distill_output_instruction`)

Then write the subagent's final table (returned as its result) to `/tmp/triage_table.md`. Explore is read-only, so if the subagent cannot write the file itself, you write it from the returned result.

## Step 6 — Report to the user

Print a short summary using the **localized labels** from `locale.triage.*`:

```
{header}. {table_path_label}: /tmp/triage_table.md

{delete_label}:   N {files_unit}, X KB
{archive_label}:  N {files_unit}, X KB
{distill_label}:  N {files_unit}, X KB → Y KB
{keep_label}:     N {files_unit}, X KB

{total_before_label}: X KB
{total_after_label}:  Y KB
{net_savings_label}:  Z KB (W%)
```

Then show 3-5 high-confidence DELETE examples under `locale.triage.high_confidence_deletes_header` and 2-3 DISTILL examples under `locale.triage.distill_examples_header`. End with `locale.triage.review_instruction`, substituting `{table_path}` with `/tmp/triage_table.md`.

---

## Triage prompt (pass to the subagent)

You're doing a **DRY-RUN** triage of a Claude Code auto-memory directory. We want to shrink it dramatically **without losing forward-looking truth**. No writes — your output is a proposal table for human review.

**Scope:** every `.md` file matching `{SCOPE_GLOB}` under `{MEMORY_DIR}`. Skip `MEMORY.md`, `*.original.md` backup files, and anything under `archive/`.

**Output language directive:** {DISTILL_OUTPUT_INSTRUCTION}

### Four possible actions per file

- **DELETE** — content is fully obsolete. Use only when at least one of:
  - Resolved bug whose fix is in the code (code is authoritative)
  - One-shot historical event with no future implication
  - Explicitly marked "RESOLVED" / "do not re-fix" / "Historical only"
  - Superseded by a newer file on the same topic
  - **Be conservative.** When unsure, prefer DISTILL.

- **ARCHIVE** — historical postmortem worth keeping for forensics but NOT daily lookup. Will be moved to `{MEMORY_DIR}/archive/` and removed from `MEMORY.md`.

- **DISTILL** — 1-3 load-bearing facts buried in prose. Provide the distilled replacement (max 3 sentences) in the table.

- **KEEP** — active state, architecture, recurring rule, or already-tight prose. If a KEEP candidate is >3 KB with narrative bloat, prefer DISTILL.

### Recognition heuristics

- Files dated `YYYYMMDD` documenting a one-day incident → usually DISTILL or ARCHIVE
- Files with "RESOLVED", "verified clean", "fixed in", "do not re-fix" → likely DELETE or ARCHIVE
- Architecture / service / protocol docs → KEEP
- Single test-run results → DISTILL to "what's now true"
- Files >5 KB with narrative prose → DISTILL aggressively

### Output format

One markdown table covering **every** file in scope, followed by a totals block. No editorializing.

```
| File | Size | Action | Reason (1 short line) | Distilled replacement (only if DISTILL) |
|---|---|---|---|---|
| foo_20260101.md | 6.2 KB | DISTILL | Dated test-run, fix is in code | Install pipeline works end-to-end as of 2026-01-01. Manual SOF firmware step still required. |
```

After the table:

```
DELETE:   N files, X KB freed
ARCHIVE:  N files, X KB freed (moved out of auto-load path)
DISTILL:  N files, X KB → Y KB (Z% reduction)
KEEP:     N files, X KB unchanged

Total before: X KB
Total after:  Y KB
Net savings:  Z KB (W%)
```

### Constraints

- Read every file before classifying it — don't classify from filename alone.
- Distilled replacements must be tight: 1-3 sentences, factual, forward-looking. Preserve any URLs, file paths, commands, or version numbers mentioned verbatim — **do not translate technical terms** even when the output language is not English.
- Preserve **"without loss"** as the top priority. Aggression is not a goal.
- Conservative with DELETE: when in doubt, ARCHIVE or DISTILL.
- Output the table + totals block. Nothing else.
