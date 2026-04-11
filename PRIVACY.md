# Privacy Policy

**Last updated: 2026-04-11**

MemPenny is a Claude Code plugin that operates entirely on your local filesystem. It collects, stores, and transmits **no data** to any external service.

## What MemPenny does with your files

MemPenny's three slash commands (`/mempenny:memory-triage`, `/mempenny:memory-apply`, `/mempenny:memory-distill`, `/mempenny:memory-compress`) touch files **only inside the auto-memory directory you explicitly target** — either your current project's directory or one you specify via `--dir <path>`. Specifically:

- **Reads** every `.md` file in the target directory (to classify it during triage or to read its body during distill/apply).
- **Writes** to files in that same directory: deletions (`rm`), moves to an `archive/` subdirectory, in-place body replacements for distilled files, and updates to `MEMORY.md`.
- **Creates a full backup** at `<memory-dir>.backup-YYYYMMDD/` before any modification. The backup is never read after creation and never transmitted.
- **Writes a dry-run proposal table** to `/tmp/triage_table.md` — a local temporary file used only for human review between a triage and an apply.

Every operation is scoped to the directory you specify. MemPenny never touches files outside that directory.

## What MemPenny does NOT do

- Make network requests of any kind
- Send telemetry, usage analytics, crash reports, or logs to any server
- Collect identifiers, email addresses, account information, or device metadata
- Store data on any server (there is no MemPenny backend — there is no server to store data on)
- Access files outside the memory directory you explicitly target
- Modify global system settings, environment variables, or configuration files
- Phone home during install, during use, or during uninstall

## Third-party components

MemPenny optionally invokes [caveman](https://github.com/JuliusBrussee/caveman)'s `compress` skill via Claude Code's Skill tool **only when the user explicitly runs `/mempenny:memory-compress`**. Caveman is a separate plugin with its own privacy properties — see its repository for details. MemPenny never calls caveman automatically, and never when the user has not run `/mempenny:memory-compress`.

## Your data stays on your machine

Every file MemPenny touches is on your own machine, in your own Claude Code auto-memory directory. MemPenny is a prompt-template plugin — there is no code (Python, JavaScript, Rust, or otherwise) that could collect, transmit, or exfiltrate data even if it wanted to. The full source is MIT-licensed and public at https://github.com/marcelopaniza/mempenny — you can audit every file in under five minutes.

## Rollback and recoverability

Because MemPenny creates a full backup before any `/mempenny:memory-apply` operation, every change is reversible with a two-line command printed in the apply output. MemPenny never deletes backups on its own — they remain in place until you remove them.

## Contact

Privacy questions, concerns, or reports: open an issue at https://github.com/marcelopaniza/mempenny/issues.

---

*This policy applies to MemPenny versions 0.2.1 and later. It does not cover caveman, Claude Code itself, or any other plugin you may have installed alongside MemPenny.*
