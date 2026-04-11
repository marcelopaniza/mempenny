---
description: Apply a previously approved triage table to a Claude Code auto-memory directory. Creates a full backup first. Rolls back on failure.
argument-hint: [<path-to-table>] [--dir <path>] [--lang <code>]
---

Apply a pre-approved triage plan to a memory directory.

## Step 1 — Parse arguments

The user invoked this command with: $ARGUMENTS

- **Table path:** first positional argument, or default `/tmp/triage_table.md` if no argument given. Verify the file exists before continuing — if missing, report using the `errors.table_not_found` message from the loaded locale.
- **`--dir <path>`** — absolute path to the memory directory to apply against. **Critical**: if the triage was run with `--dir`, the apply **must** be run with the same `--dir` so the table lines up with the right target dir. If not set, auto-detect the current project's memory dir (same logic as `/memory-triage`).
- **`--lang <code>`** — language for the user-visible summary. If not passed, check `MEMPENNY_LOCALE`. Default `en`.

## Step 2 — Load locale strings

Read `${CLAUDE_PLUGIN_ROOT}/locales/<lang>/strings.json`. Fall back to `en` if missing (and warn using `errors.locale_missing`). You need `apply.*` labels for the final summary.

## Step 3 — Spawn the apply subagent

Use the Agent tool with:

- `subagent_type: general-purpose` (needs Write/Edit/Bash)
- `model: sonnet` (mechanical execution)
- `prompt`: the apply prompt below, parameterized with `{TABLE_PATH}` and `{MEMORY_DIR}`

Run in foreground — you need the result to show the user.

## Step 4 — Relay the result

When the subagent returns, render its results using the localized `apply.*` labels from `strings.json`. Example shape (substitute real values):

```
{backup_label}: <path> (<N> files, {backup_verified_suffix})

{delete_label}:   <N>/<total> {succeeded_label}
{archive_label}:  <N>/<total> {succeeded_label}
{distill_label}:  <N>/<total> {succeeded_label}

{memory_md_label}:  <before> → <after> {memory_md_lines_suffix} (<delta>)

{bytes_header}:
  {main_before_label}:  X
  {main_after_label}:   Y   ({main_after_suffix})
  {archive_label}:      Z
  {net_savings_label}:  W  (P%)
```

(Use the `triage.*` keys — `delete_label`, `archive_label`, `distill_label` — since the apply summary reuses the same bucket names.)

End with the rollback instructions in a code block so the user can copy-paste if needed. Use `apply.rollback_comment` as the comment line:

```
# {rollback_comment}
rm -rf <MEMORY_DIR>/
mv <MEMORY_DIR>.backup-YYYYMMDD/ <MEMORY_DIR>/
```

After the rollback block, print the localized **next-step suggestion** from `apply.next_step_header` and `apply.next_step_suggestion`, substituting `{dir}` with the target directory. Example (en):

```
**Next step**

Run `/mempenny:memory-compress --dir <MEMORY_DIR>` to compress the surviving prose with caveman (if installed). MemPenny removes what shouldn't be there; caveman shrinks what's left.
```

This is a suggestion, not an automatic action. The user runs compress when ready. If they don't have caveman, `/mempenny:memory-compress` will detect that and print install instructions rather than modifying anything.

---

## Apply prompt (pass to the subagent)

You are applying a pre-approved memory triage plan. The plan is a markdown table at `{TABLE_PATH}` with columns:

`File | Size | Action | Reason | Distilled replacement (only if Action = DISTILL)`

**Target directory:** `{MEMORY_DIR}`

### Actions

- **DELETE** — `rm` the file in the main dir
- **ARCHIVE** — `mv` the file into `{MEMORY_DIR}/archive/`
- **DISTILL** — preserve YAML frontmatter exactly, replace the body with the distilled replacement from the table, write back
- **KEEP** — skip, no action

### CRITICAL pre-step: backup

Before any modification:

```bash
cp -a {MEMORY_DIR}/ {MEMORY_DIR}.backup-$(date +%Y%m%d)/
```

Verify the backup directory exists and file count matches the source. If the backup fails, STOP immediately and return an error. Do NOT continue.

### Apply order

1. Back up (as above).
2. `mkdir -p {MEMORY_DIR}/archive/`.
3. For each DELETE row in the table: verify the file still exists, then `rm` it. Track successes and failures.
4. For each ARCHIVE row: `mv` the file into `{MEMORY_DIR}/archive/`. Track successes and failures.
5. For each DISTILL row:
   - Read the file.
   - **If it starts with `---` YAML frontmatter**, preserve the frontmatter block character-for-character and replace the body (everything after the closing `---`) with the distilled replacement text from the table.
   - **Else if it starts with a `#` markdown heading line**, preserve that heading line and replace everything after it with the distilled replacement text. This keeps the file's title visible when the original author used a markdown heading instead of frontmatter.
   - **Otherwise**, replace the entire file contents with the distilled replacement text.
   - Keep a trailing newline in all three cases.
   - Write back with the Write tool.
6. Update `{MEMORY_DIR}/MEMORY.md`:
   - Remove any `- [filename.md](filename.md) - ...` line whose file was DELETED or ARCHIVED.
   - Leave DISTILLED entries alone — their description doesn't change just because the body shrank.
   - Preserve all section headers, even ones that become empty.

### Rollback policy

If ≥5% of actions in ANY bucket fail, STOP after that bucket and report. Do NOT auto-rollback — the user decides whether to restore from backup.

### Idempotent semantics

If a DELETE target is already absent, or an ARCHIVE target is already in `archive/`, count that as a success (the intent is satisfied). Do not error.

### Constraints

- Do not modify files outside `{MEMORY_DIR}`.
- Do not touch the backup after creation.
- Skip `MEMORY.md` itself, `*.original.md`, and anything under `archive/` — none of those appear in the table.
- Files with prefixes the table doesn't mention (`feedback_*.md`, `user_*.md`, etc.) are skipped implicitly — they simply don't appear in the table.

### Bash safety note

If you use a bash counter inside a loop while the script has `set -e` active (explicit or via shopt), **do not** use `((count++))` — it exits with code 1 when the pre-increment value is 0, which trips `set -e` and aborts the loop. Use `count=$((count+1))` instead, which always exits 0. This applies to any success/failure tallies you build during the DELETE / ARCHIVE / DISTILL passes.

### Return format

```
BACKUP: <path> (<N> files, verified)

DELETE:   <N>/<total> succeeded   [list any real failures with reason]
ARCHIVE:  <N>/<total> succeeded   [list any failures]
DISTILL:  <N>/<total> succeeded   [list any failures]

MEMORY.md:  <before> lines → <after> lines (<delta>)

Bytes:
  Main dir before:  X
  Main dir after:   Y   (excluding archive/)
  Archive:          Z
  Net savings:      W  (P%)

<warnings, if any>
```

(The outer `/memory-apply` command will re-render these labels in the user's locale before showing to the user — your subagent output can stay in English.)
