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

MemPenny operates on the user's local machine, on files in `~/.claude/projects/<id>/memory/`. Memory file contents are treated as **untrusted data** — the plugin never executes content from a memory file, rejects symlinks at sensitive paths, and never accepts shell metacharacters in paths.

Specific guardrails (codenames in source):

- **Path traversal (C1):** every absolute-path config value passes a tight regex `^/[A-Za-z0-9/_.\ -]{1,4096}$` and a `realpath` resolution before use.
- **Symlink attacks (F-M2):** symlink guards on `~/.claude/mempenny.config.json` and `~/.claude/settings.json` reads and writes, with TOCTOU re-checks immediately before mutation.
- **Filename injection (H1):** filenames in triage tables are validated against `^[A-Za-z0-9][A-Za-z0-9_.\-]*\.md$` before any `rm` or `mv`.
- **Prompt injection in memory bodies (H2):** subagent prompts treat file bodies as data; locked-file marker check runs before content rubric.
- **Backup integrity (M4 + M6):** every modification is preceded by a `cp -a` backup with a SHA-256 manifest; explicit ordering between backup and apply.
- **Confirm-then-write (M3):** `AskUserQuestion` cancellation always writes nothing.
- **Permissions (L1):** config and settings writes are `chmod 600`; backup folders are `chmod 700`.
- **Isolated apply + scripted verification (v1.1+):** the topic-taxonomy migration, `/mempenny:memory-curate`, and `/mempenny:memory-shard-roll` all run their actual writes in a separately-spawned subagent with no memory of the proposal step, never in the same context that read the untrusted source content. Migration and shard-roll additionally run without a confirmation prompt; the property that makes that safe is a scripted (not judgment-based) verification that every relocated line survived, run before anything old is deleted — see `docs/memory-taxonomy-design.md` for the full rationale.

## What we don't promise

- Protection against an already-compromised system, root-level attacker, or kernel exploits.
- Protection against attacks via maliciously-set environment variables (`HOME`, `TMPDIR`).
- Protection against AI prompt-injection bypass that defeats the in-prompt H2 guardrails — please report any such observation.

## Lock controls

Users can opt files or directories out of MemPenny entirely:

- **Folder lock:** `.mempenny-lock` (or `.mempenny-fixture`) empty file in the memory directory — every command refuses to operate.
- **File lock:** `<!-- mempenny-lock -->` HTML comment in any memory file — `/clean` classifies as KEEP, `/memory-distill` refuses.

## opencode host (added in v1.2)

The `.opencode/` layer adds a second host. The Claude Code threat model above still holds verbatim for `commands/` and `hooks/`; this section documents the *new* surface and the guards specific to it. Codenames refer to the existing guards; the new code lives in `.opencode/plugins/`.

- **Env-var namespace (no `CLAUDE_*` collision).** The env shim (`mempenny-env.ts`) injects only `MEMPENNY_HOST` / `MEMPENNY_ROOT` / `MEMPENNY_DATA_DIR` via the `shell.env` hook. It deliberately does **not** set `CLAUDE_PROJECT_DIR` / `CLAUDE_PLUGIN_ROOT` / `CLAUDE_PLUGIN_DATA` — those are left to a real Claude Code process. The command adapters instruct the model to substitute the references at read time, so a machine running both hosts cannot have one host's env vars override the other's.
- **Install is clone-and-run, not `curl | bash`.** `install/opencode.sh` copies the host-agnostic tree into `~/.local/share/mempenny` as a **stable snapshot** and symlinks only the opencode-discovery files (commands + plugins) from `~/.config/opencode/` at that snapshot. The symlinks never point at a live git checkout, so a compromised upstream or `git pull` cannot silently change executed code — updates require re-running the installer.
- **TS plugins re-run every path guard.** `.opencode/plugins/_paths.ts` ports C1 (path regex), H1 (filename regex), and F-M2 (symlink refusal) into TypeScript. `mempenny-nap.ts` validates every path through it before any `readFileSync` / `writeFileSync` / `mkdirSync`; no filesystem call happens on an unvalidated or symlinked path.
- **Nap is notify-only.** `session.created` fires a desktop notification pointing the user at `/mempenny-clean --yes`; it does **not** auto-invoke a destructive cleanup. Auto-invoke is reserved for a future release behind an explicit `nap.mode: "auto"` opt-in, so a scheduled nap cannot run a destructive operation without a prompt in v1.2.
- **Permissions.** The installer tightens the snapshot (dirs `700`, `*.json` `600`); the nap plugin writes its state file `0o600`.
- **No path leakage in logs.** The nap plugin logs the `sha1-12` hash of the memory directory, not the path itself.

The `AGENTS.md` rules-only tier (for Codex/Gemini/CodeWhale/Swival/etc.) introduces no new executable surface — it is passive text the host reads. Its safety guidance reiterates backup-first, conservation, path/filename validation, and treating file bodies as untrusted data; it does not and cannot enforce them the way the installed commands do. Hosts on that tier rely on the model following the documented discipline.

## opencode UX layer (added in v1.3)

Two additions that reduce per-run friction **without** weakening the safety model. Blast radius is the opencode host only; Claude Code and every other host are unaffected (`.opencode/` is opencode-only).

- **Scoped `mempenny` agent.** The opencode commands run under a dedicated agent (`.opencode/agents/mempenny.md`) whose permissions are pre-relaxed only for mempenny's known-safe operations: a bash allowlist derived from the real command vocabulary (reads, search, create, copy, chmod, atomic-rename `mv`), plus `external_directory` pre-allowed only for mempenny's own paths (`~/.claude/projects/**`, the config files, `~/.local/share/mempenny/**`). **`rm` and any unlisted command still prompt** — that is the one insurance line kept on by design. The relaxation applies only while a mempenny command is the active agent (the adapters set `agent: mempenny`); all other workflows keep the default posture. The commands' own in-prompt guards (backup-first, conservation, H2 untrusted-bodies) are unchanged. Triage/apply subagents run under their own agent profiles; to suppress their `external_directory` prompts too, run with `--auto` or add a global rule.
- **Apply tools.** `mempenny-backup` and `mempenny-read-config` (`.opencode/plugins/mempenny-apply.ts`) port only low-stakes deterministic bash into TypeScript; every path is re-validated through `_paths.ts` (C1 + F-M2). The hardened conservation check and the write/verify landing script are **deliberately not ported** — v1.1.4 settled their bash and a TS re-port would re-open those bugs; they stay bash everywhere.

## multi-host adapter files (added in v1.3)

v1.3 adds the per-host adapter files other agents expect: plugin manifests (`.codex-plugin/plugin.json`, `gemini-extension.json`, `.devin-plugin/plugin.json`, `plugin.yaml`, `.agents/plugins/marketplace.json`), rules files (`.cursor/rules/mempenny.mdc`, `.windsurf/rules/mempenny.md`, `.clinerules/mempenny.md`, `.kiro/steering/mempenny.md`, `.github/copilot-instructions.md`, `.agents/rules/mempenny.md`), and a skill (`.openclaw/skills/mempenny/SKILL.md`).

All of these are **passive** — either a JSON/YAML manifest pointing the host at `AGENTS.md`, or markdown text the host reads. None introduce executable surface, hooks, or code on their target hosts; the rules content is a compact distillation of `AGENTS.md` and reiterates the same guards (backup-first, conservation, path/filename validation, untrusted file bodies, off-limits markers). The rules-only tier relies on the model following that documented discipline; it cannot enforce the way the installed commands on Claude Code / opencode do. Formats were verified against a working reference (the ponytail plugin's shipped adapters), not guessed.
