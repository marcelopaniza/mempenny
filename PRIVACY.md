# Privacy Policy

**Last updated: 2026-04-19** (v0.5.1)

MemPenny is a Claude Code plugin that operates entirely on your local filesystem. It collects, stores, and transmits **no data** to any external service.

## What MemPenny does with your files

MemPenny's slash commands (`/mp:clean`, `/mp:restore`, `/mp:memory-triage`, `/mp:memory-apply`, `/mp:memory-distill`, `/mp:memory-compress`) touch files **only inside the auto-memory directory you explicitly target** — either your current project's directory or one you specify via `--dir <path>` — plus a single small config file at `~/.claude/mempenny.config.json`. Specifically:

- **Reads** every `.md` file in the target directory (to classify it during triage or to read its body during distill/apply).
- **Writes** to files in that same directory: deletions (`rm`), moves to an `archive/` subdirectory, in-place body replacements for distilled files, and updates to `MEMORY.md`.
- **Creates a full backup** before any modification. `/mp:clean` and `/mp:memory-apply` (when `~/.claude/mempenny.config.json` has an entry for the current memory directory) both write to the user-configured backup folder as `<backup-folder>/memory.backup-YYYYMMDDHHMMSS-PID/`; when no entry exists for the current memory dir, `/mp:memory-apply` falls back to `<memory-dir>.backup-YYYYMMDDHHMMSS-PID/` alongside the memory directory. Backup directories are created with permissions 700 and the config file is stored at 600 — readable only by your user account. Backups are never read after creation (except by `/mp:restore`, at your explicit request) and never transmitted.
- **Writes a dry-run proposal table** to a private `mktemp`-generated path (e.g., `/tmp/mempenny-triage-XXXXXXXX.md`) with permissions `600`. A local temporary file used only for human review between a triage and an apply. (Before v0.4.1 this was a fixed `/tmp/triage_table.md` with default perms; moved to `mktemp 600` in v0.4.1 to prevent cross-user read/pre-poisoning on shared systems.)
- **Writes a local config file** at `~/.claude/mempenny.config.json` on first run of `/mp:clean` in each memory directory (v0.5+ per-dir schema) — stores only the absolute paths to the memory directories you've cleaned and the absolute paths to the backup folders you chose for each. No identifiers, no telemetry, no paths outside what you explicitly entered. Upgrading from v0.4.x auto-migrates the legacy single-folder schema to the per-dir schema on first v0.5 run; no new data is added to the file beyond the paths you already supplied.

Every operation is scoped to the directory you specify (plus the config file above). MemPenny never touches files outside that scope.

## What MemPenny does NOT do

- Make network requests of any kind
- Send telemetry, usage analytics, crash reports, or logs to any server
- Collect identifiers, email addresses, account information, or device metadata
- Store data on any server (there is no MemPenny backend — there is no server to store data on)
- Access files outside the memory directory you explicitly target
- Modify global system settings, environment variables, or configuration files
- Phone home during install, during use, or during uninstall

## Third-party components

MemPenny optionally invokes [terse-md](https://github.com/marcelopaniza/terse-md)'s `run` skill via Claude Code's Skill tool in two places: (1) at the end of a successful `/mp:clean` run, when terse-md is installed, to compress the surviving memory files; (2) when the user explicitly runs `/mp:memory-compress`. In both cases, MemPenny passes only the memory directory path (plus pass-through `--dry-run` / `--include-all` flags from the user) — no file contents, no identifiers, nothing else. If terse-md is not installed, MemPenny prints a one-paragraph install hint and does nothing. Terse-md is a separate plugin with its own privacy properties — see its repository for details.

## Your data stays on your machine

Every file MemPenny touches is on your own machine, in your own Claude Code auto-memory directory. MemPenny is a prompt-template plugin — there is no code (Python, JavaScript, Rust, or otherwise) that could collect, transmit, or exfiltrate data even if it wanted to. The full source is MIT-licensed and public at https://github.com/marcelopaniza/mempenny — you can audit every file in under five minutes.

## Threat model note: prompt injection

MemPenny itself ships no executable code — but it reads the contents of your memory files and passes them through Claude subagents during triage and apply. If a memory file's contents were themselves adversarial (e.g., placed there by another process on your machine), they could theoretically instruct Claude to take actions outside MemPenny's scope using Claude Code's own tools (Bash, web fetches). That is a property of the Claude Code runtime, not of MemPenny.

v0.4.1 hardens both subagents to treat file contents and table rows as passive data, never as instructions. If you suspect tampering in your memory directory, diff against the most recent backup before running `/mp:clean`. If `~/.claude/mempenny.config.json` looks unfamiliar (paths containing `$`, backticks, or other shell characters), delete it and re-run `/mp:clean` — the config is regenerable, never load-bearing.

## Rollback and recoverability

Because MemPenny creates a full backup before any `/mp:clean` or `/mp:memory-apply` operation, every change is reversible — via `/mp:restore` for clean backups, or the two-line command printed in memory-apply output. MemPenny never deletes backups on its own — they remain in place until you remove them.

## Contact

Privacy questions, concerns, or reports: open an issue at https://github.com/marcelopaniza/mempenny/issues.

---

*This policy applies to MemPenny versions 0.5.1 and later. It does not cover terse-md, Claude Code itself, or any other plugin you may have installed alongside MemPenny.*
