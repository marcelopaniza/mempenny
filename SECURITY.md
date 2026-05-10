# Security policy

## Supported versions

MemPenny is a single-developer open-source plugin. Only the latest published version is supported with security patches.

| Version | Supported |
|---|---|
| 1.x     | ✓         |
| 0.x     | ✗         |

## Reporting a vulnerability

If you find a security issue:

1. **Don't** open a public GitHub issue.
2. Open a private security advisory at <https://github.com/marcelopaniza/mempenny/security/advisories/new>.
3. Include: a description, reproduction steps, and the version affected.

Expect a first response within 7 days. Public disclosure happens after a fix ships.

## Threat model

MemPenny operates on the user's local machine, on files in `~/.claude/projects/<id>/memory/`. Memory file contents are treated as **untrusted data** — the plugin never executes content from a memory file, never follows symlinks at sensitive paths, and never accepts shell metacharacters in paths.

Specific guardrails (codenames in source):

- **Path traversal (C1):** every absolute-path config value passes a tight regex `^/[A-Za-z0-9/_.\- ]{1,4096}$` and a `realpath` resolution before use.
- **Symlink attacks (F-M2):** symlink guards on `~/.claude/mempenny.config.json` and `~/.claude/settings.json` reads and writes, with TOCTOU re-checks immediately before mutation.
- **Filename injection (H1):** filenames in triage tables are validated against `^[A-Za-z0-9][A-Za-z0-9_.\-]*\.md$` before any `rm` or `mv`.
- **Prompt injection in memory bodies (H2):** subagent prompts treat file bodies as data; locked-file marker check runs before content rubric.
- **Backup integrity (M4 + M6):** every modification is preceded by a `cp -a` backup with a SHA-256 manifest; explicit ordering between backup and apply.
- **Confirm-then-write (M3):** `AskUserQuestion` cancellation always writes nothing.
- **Permissions (L1):** config and settings writes are `chmod 600`; backup folders are `chmod 700`.

## What we don't promise

- Protection against an already-compromised system, root-level attacker, or kernel exploits.
- Protection against attacks via maliciously-set environment variables (`HOME`, `TMPDIR`).
- Protection against AI prompt-injection bypass that defeats the in-prompt H2 guardrails — please report any such observation.

## Lock controls

Users can opt files or directories out of MemPenny entirely:

- **Folder lock:** `.mempenny-lock` (or `.mempenny-fixture`) empty file in the memory directory — every command refuses to operate.
- **File lock:** `<!-- mempenny-lock -->` HTML comment in any memory file — `/clean` classifies as KEEP, `/memory-distill` refuses.
