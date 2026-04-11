---
description: Compress prose in every memory file in a directory via caveman. Runs caveman:compress on each surviving .md file, shrinks prose without touching code, commands, URLs, or version numbers. Requires caveman installed.
argument-hint: [--dir <path>] [--only <glob>] [--lang <code>]
---

Compress every `.md` file in a memory directory by invoking the `caveman:compress` skill on each file individually. Caveman preserves all technical substance (code, URLs, paths, commands, version numbers, frontmatter) and shrinks only the prose. Each file is backed up by caveman as `FILE.original.md` before being overwritten.

This is the final step after `/mempenny:memory-triage` + `/mempenny:memory-apply`. Run it on the same directory to compress the surviving KEEP + DISTILL files.

## Step 1 — Parse arguments

The user invoked this command with: $ARGUMENTS

Parse three optional arguments from `$ARGUMENTS`:

- `--dir <path>` — absolute path to the memory directory. If set, use verbatim; otherwise auto-detect the current project's memory dir (same logic as `/memory-triage`).
- `--only <glob>` — scope filter (e.g., `--only project_*.md`). Default: every `.md` file directly under the memory dir. Multiple globs can be comma-separated.
- `--lang <code>` — output language for user-visible labels. If not passed, check `MEMPENNY_LOCALE`. Default `en`.

## Step 2 — Load locale strings

Read `${CLAUDE_PLUGIN_ROOT}/locales/<lang>/strings.json`. Fall back to `en` and warn with `errors.locale_missing` if missing. You need `compress.*` labels for the summary and `errors.caveman_not_installed` for the fallback message.

## Step 3 — Verify caveman is installed

**Check the currently-available skills list** (it's in your system context at the top of every conversation). Look for a skill named `caveman:compress` — the skill responsible for compressing natural language memory files.

**If `caveman:compress` is NOT in your skills list:**

Print the localized `errors.caveman_not_installed` message (substituting `{dir}` with the target directory so the user knows where to retry). Do NOT modify any files. STOP.

The default English fallback message is:

> Caveman is not installed. MemPenny's triage removes what shouldn't be there; caveman compresses what's left. To install:
>
> ```
> /plugin marketplace add JuliusBrussee/caveman
> /plugin install caveman@caveman
> /reload-plugins
> ```
>
> Then re-run `/mempenny:memory-compress --dir {dir}`.

**If `caveman:compress` IS in your skills list**, proceed to Step 4.

## Step 4 — Locate the memory directory

Same logic as `/memory-triage`:

- If `--dir` was passed, use it verbatim. Verify the directory exists and contains at least one `.md` file.
- Otherwise, auto-detect `~/.claude/projects/<project-id>/memory/` from the current project. If uncertain, ask the user (use `errors.memory_dir_not_found`).

## Step 5 — Determine scope

**Default scope:** every `.md` file directly under the memory directory, **excluding**:
- `MEMORY.md` (never compress the index — its format matters for auto-discovery)
- `*.original.md` (caveman's own backups — compressing them would double-compress)
- `*.backup.md`, `*.bak.md` (other common backup patterns)
- Anything under `archive/` (those are by definition out-of-active-load; compressing is wasted effort)

If `--only <glob>` was passed, further narrow to that pattern. Multiple globs comma-separated.

Use the Glob tool to list matching files. If zero files match, print a friendly "nothing to compress" message using locale labels and STOP.

## Step 6 — Record pre-compression sizes

Before invoking caveman on any file, record the total byte size of all files in scope. You'll need this for the final savings report.

Use Bash: `find <dir> -maxdepth 1 -type f -name '*.md' <exclusions> | xargs du -b | awk '{s+=$1} END {print s}'`

Or iterate file-by-file with Read and count lengths. Either works — pick whichever is cleaner.

## Step 7 — Invoke caveman:compress on each file

For each file in scope, invoke the `caveman:compress` skill via the Skill tool with the **absolute path** to the file as its argument. Example:

```
Skill(skill: "caveman:compress", args: "/home/user/.claude/projects/-some-project/memory/project_foo.md")
```

Caveman will:
1. Detect file type (no tokens)
2. Back up the file to `<filename>.original.md`
3. Compress the prose, preserving all code/URLs/paths/commands/frontmatter
4. Overwrite the original file with compressed content
5. Return a short status

**Track per-file outcome:** success or failure (with reason). Caveman handles its own backup, so you do NOT need to create a separate backup — each file gets its own `.original.md` alongside.

If ≥20% of files fail in a row, STOP after that batch and report. This probably means caveman is broken, not that individual files are bad.

## Step 8 — Record post-compression sizes and report

After all invocations complete, measure total bytes of the same files (now compressed) and compute:

- `files_compressed` / `files_total`
- `bytes_before` (from Step 6)
- `bytes_after` (measured now)
- `net_savings` = `bytes_before - bytes_after`
- `ratio` = `bytes_after / bytes_before` as a percentage

Print a summary using localized `compress.*` labels. Template (en):

```
{header}. {files_label}: {files_compressed}/{files_total} {compressed_label}

{bytes_header}:
  {before_label}:  X B
  {after_label}:   Y B
  {savings_label}: Z B ({ratio}%)

{backup_note}
```

Where `{backup_note}` is the locale's compress.backup_note — a short reminder that caveman created `<file>.original.md` for each compressed file, and rollback is `mv <file>.original.md <file>` per file.

If any files failed, list them in a `{warnings_header}` block with the per-file failure reason.

## Step 9 — Rollback instructions

End with a localized rollback tip in a code block so the user can copy-paste. Each file is independently reversible by moving its `.original.md` sibling back into place:

```
# Rollback a single file
mv <file>.original.md <file>

# Rollback all files in a dir
for f in <dir>/*.original.md; do mv "$f" "${f%.original.md}.md"; done
```

---

## Constraints

- **Never compress `MEMORY.md`** — its markdown structure is parsed by Claude Code for auto-discovery. Caveman-style compression could break the parse.
- **Never compress `*.original.md`** — those are caveman's own backups. Double-compression produces nonsense.
- **Never compress files under `archive/`** — archived files are by definition out of the auto-load path; compression is wasted effort.
- **Do not modify `.claude-plugin/`, `.git/`, or any non-memory path** — only operate inside `{MEMORY_DIR}`.
- **Respect caveman's own boundaries** — caveman refuses to touch `.py`, `.js`, `.json`, `.yaml`, etc. If a user somehow puts a `.js` file in their memory dir (unusual), caveman will skip it and return a non-error status; count that as a "skipped" outcome, not a failure.
- If the user Ctrl-Cs mid-batch, some files will already be compressed and others not. That's fine — the command is idempotent per-file (a second run on a compressed file just re-compresses minimally, and the `.original.md` backup chain protects them).
