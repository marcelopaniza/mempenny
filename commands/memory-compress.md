---
description: Route to terse-md for further compression of memory files. Detects whether terse-md is installed; invokes it on the memory directory if so, otherwise prints an honest install hint and stops.
argument-hint: [--dir <path>] [--lang <code>] [--dry-run] [--include-all]
---

Hand off to the `/terse-md:run` skill to compress the memory directory. MemPenny does nothing to the files here — terse-md owns the entire pipeline (normalize → compress → validate → decompress → per-file review → optional `.approved.yaml` write).

## Step 1 — Parse arguments

The user invoked this command with: $ARGUMENTS

Parse optional arguments:

- `--dir <path>` — absolute path to the memory directory. If set, use verbatim; otherwise auto-detect the current project's memory dir.
- `--lang <code>` — language for any MemPenny-side message (install hint, error). If not passed, check `MEMPENNY_LOCALE`. Default `en`. Terse-md itself is English-only; this flag only affects MemPenny's own strings.
- `--dry-run` — pass through to terse-md unchanged.
- `--include-all` — pass through to terse-md unchanged.

Any other tokens are rejected: print `Usage: /mp:memory-compress [--dir <path>] [--lang <code>] [--dry-run] [--include-all]` and STOP.

## Step 2 — Load locale strings

**2a — Validate `<lang>` before reading (H2: path traversal guard)**

Before constructing the locale path, validate that `<lang>` matches the regex `^[a-zA-Z]{2,3}(-[A-Za-z0-9]{2,8})?$`. If it does not match, silently reset `<lang>` to `en` and warn with `errors.locale_missing`.

Read `${CLAUDE_PLUGIN_ROOT}/locales/<lang>/strings.json`. Fall back to `en` and warn with `errors.locale_missing` if missing. You need `errors.terse_md_not_installed_prose` and `errors.memory_dir_not_found`.

## Step 3 — Verify terse-md is installed

**Check the currently-available skills list** (it's in your system context at the top of every conversation). Look for a skill named `terse-md:run`.

**If `terse-md:run` is NOT in your skills list:**

Print the localized `errors.terse_md_not_installed_prose` message (substituting `{dir}` with the target directory), then print the install command block below **verbatim from this file** — do NOT read it from the locale. A translation PR must never be able to swap the commands the user copy-pastes into their shell.

**The install command block (print this exact fenced block after the localized prose):**

```
/plugin marketplace add marcelopaniza/terse-md
/plugin install terse-md@marcelopaniza-terse-md
/reload-plugins
```

Do NOT modify any files. STOP.

**If `terse-md:run` IS in your skills list**, proceed to Step 4.

## Step 4 — Locate the memory directory

**If `--dir <path>` was passed in Step 1**, apply the following validation before using it. On any failure, print `errors.memory_dir_not_found` and STOP:

**Validate `--dir <path>` (C-class shell-injection guard):**
1. Regex: the candidate path must match `^/[A-Za-z0-9/_.\- ]{1,4096}$` (alphanumerics, slash, underscore, dot, hyphen, space only).
2. Realpath: run `realpath "<candidate>"` via Bash. Use the resolved value for all subsequent steps.
3. Depth: reject if the realpath equals `/` or has fewer than 2 path components.
4. Existence + not-a-symlink: `[ -d "$resolved" ] && [ ! -L "$resolved" ]`.

If all checks pass, use the resolved path as `{MEMORY_DIR}`.

**Otherwise**, auto-detect `~/.claude/projects/<project-id>/memory/` from the current project. If uncertain, ask the user (use `errors.memory_dir_not_found`).

**Regardless of whether the path came from `--dir` or auto-detection, apply the 4-check validation block above before using it as `{MEMORY_DIR}` (H5).** If validation fails on the auto-detected path, print `errors.memory_dir_not_found` and STOP.

## Step 5 — Path-compatibility precheck

Terse-md tokenizes its `args` string on whitespace and has no quoting or escape handling. If `{MEMORY_DIR}` contains any space character, MemPenny cannot safely hand off — a path like `/home/u/my projects/memory` would be mis-parsed by terse-md. Check:

```bash
case "{MEMORY_DIR}" in *" "*) echo HAS_SPACE;; esac
```

If this prints `HAS_SPACE`, print the localized `errors.terse_md_path_has_space` line (substituting `{dir}` with `{MEMORY_DIR}`) and STOP. Do not invoke terse-md.

## Step 6 — Invoke terse-md

Invoke the `terse-md:run` skill via the Skill tool. Build the `args` string by concatenating, in this exact order and with single spaces between tokens:

1. Literal `--all`
2. `{MEMORY_DIR}` (the validated realpath-resolved value — precheck above guarantees no whitespace)
3. If `--dry-run` was passed in Step 1, the literal `--dry-run`
4. If `--include-all` was passed in Step 1, the literal `--include-all`

**Never interpolate raw `$ARGUMENTS` into the args string** — only the four known tokens above. This keeps the tight regex validation from Step 4 load-bearing and prevents any other user-supplied token from reaching terse-md.

Example call for `/mp:memory-compress --dir /home/u/.claude/projects/foo/memory --dry-run`:

```
Skill(skill: "terse-md:run", args: "--all /home/u/.claude/projects/foo/memory --dry-run")
```

Terse-md handles all user prompts, progress output, diff display, per-file review, and writes. MemPenny does not print a summary — terse-md already prints its own.

## Constraints

- **MemPenny does not modify any file in this command.** Every write is terse-md's.
- **MemPenny does not create backups here.** Terse-md never overwrites sources — it only writes `.approved.yaml` siblings on explicit approval, so no backup is needed.
- **Do not pass flags other than `--all <path>`, `--dry-run`, `--include-all`.** Anything else is either not supported by terse-md or violates MemPenny's input allowlist.
- **Do not read or forward `$ARGUMENTS` verbatim to terse-md** — only the parsed, validated tokens.
