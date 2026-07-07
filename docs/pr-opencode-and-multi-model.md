# PR Plan — OpenCode Host Support + Multi-Model Compatibility

**Status:** Draft, awaiting implementation
**Proposed branch:** `feat/opencode-multi-model`
**Target version:** `v1.2.0` (new minor — additive, no breaking changes to locked surface)
**Author context:** Research performed from an opencode session running GLM, against a Claude Code-populated memory dir at `~/.claude/projects/-mnt-data-myproject/memory/`.

---

## TL;DR

Make mempenny installable and reliable on **opencode** as a first-class host (alongside Claude Code), and make its prompts reliable on **any competent coding model** (Claude Sonnet/Opus, GLM 4.6+, GPT-5, Gemini 2.5) — not just Claude. One source tree, two host layouts, model-agnostic prompt language.

The plugin today is Claude Code-only by packaging and Claude-tuned by phrasing. The underlying mechanics (markdown commands, locale JSON, bash hook, file-system operations on a memory dir) are portable. This PR adds the parallel packaging and rephrases the prompts without rewriting the logic.

---

## Background

MemPenny today:

- Packaged as a Claude Code plugin (`.claude-plugin/{plugin,marketplace}.json`).
- Installed via `/plugin marketplace add marcelopaniza/mempenny` + `/plugin install mempenny@mempenny`.
- Commands at `commands/*.md` (8 files, 4,039 lines total; `clean.md` alone is 1,841).
- `SessionStart` hook at `hooks/nap-check.sh` (91 lines bash).
- Skill at `skills/memory-hygiene/SKILL.md`.
- Config at `~/.claude/mempenny.config.json` (schema v2, per-memory-dir).
- Memory dir auto-resolved from `CLAUDE_PROJECT_DIR` via the slug rule `sed 's|/|-|g; s|^-||'` → `~/.claude/projects/<slug>/memory/`.
- Auto-memory enable offer reads `~/.claude/settings.json` → `autoMemoryEnabled`.
- Locales at `locales/{en,es,pt-BR}/strings.json` (portable, no work needed).

---

## Goals

1. **Install on opencode** with one command; no manual file copying.
2. **All 8 commands work on opencode** when invoked as slash commands (`/mempenny-clean` etc.).
3. **Nap scheduler works on opencode** via `session.created` event hook (TS plugin replaces the bash hook).
4. **Memory dir auto-resolution finds Claude-populated dirs** from an opencode session in the same project (shared memory, zero setup for users running both hosts).
5. **Prompt language is model-agnostic** — no Claude-specific tool names, subagent syntax, or implication-based instruction. Strict output schemas so weaker-instruction-following models stay reliable.
6. **README advertises** the supported host × model matrix.
7. **Claude Code path unchanged.** Existing users see zero behavior change.

## Non-goals

- **Not** building an opencode auto-memory tool (opencode has no equivalent of Claude Code's `memory` tool; mempenny-on-opencode stays read/clean/restore-only for now). Tracked separately as a future v1.3.
- **Not** rewriting the prompt logic, security guards, locale schema, or taxonomy. The 4,000 lines of carefully-hardened command text stays.
- **Not** changing the backup format, config schema, or any locked surface from v1.0+.
- **Not** adding new locales.

---

## Two compat axes (recap)

These are largely independent and ship as separable commits:

| Axis | What | Touches |
|---|---|---|
| **Host** (opencode) | Plugin runs *on opencode* | Packaging, install, hooks, env vars, paths, command names |
| **Model** (GLM et al.) | Prompts produce reliable output *on non-Claude models* | Command markdown phrasing, output schemas, subagent references |

---

## Axis 1 — Host compat: gap-by-gap

Findings reference real files in this repo.

### 1.1 Packaging — `.claude-plugin/` manifest

**Gap:** `.claude-plugin/{plugin,marketplace}.json` is Claude Code's plugin manifest format. Opencode ignores it entirely. Opencode plugins are JS/TS modules auto-loaded from `~/.config/opencode/plugins/` (global) or `.opencode/plugins/` (project), or installed from npm via `opencode.json` → `plugin: [...]`.

**Fix:** Add a parallel `.opencode/` layout in the same repo. Do not remove the Claude layout.

```
mempenny/
  .claude-plugin/            # Claude Code manifest (UNCHANGED)
    plugin.json
    marketplace.json
  commands/                  # Claude Code slash commands (UNCHANGED)
    clean.md
    ...
  hooks/                     # Claude Code SessionStart hook (UNCHANGED)
    hooks.json
    nap-check.sh
  .opencode/                 # NEW — opencode layout
    commands/                #   commands (markdown, opencode frontmatter)
      mempenny-clean.md
      mempenny-nap.md
      mempenny-restore.md
      mempenny-memory-triage.md
      mempenny-memory-apply.md
      mempenny-memory-distill.md
      mempenny-memory-curate.md
      mempenny-memory-shard-roll.md
    plugins/                 #   TS plugins
      mempenny-nap.ts        #   replaces hooks/nap-check.sh
      mempenny-env.ts        #   exposes env vars (see 1.4)
  skills/memory-hygiene/     # ALREADY portable — opencode reads ~/.claude/skills natively
    SKILL.md
  locales/                   # UNCHANGED — portable JSON
  ...
```

### 1.2 Command namespacing — `/mempenny:clean` → `/mempenny-clean`

**Gap:** Claude Code uses `plugin:command` namespace (colon). Opencode command names come from the filename; `:` is filesystem-unsafe on Windows and ugly on Linux.

**Fix:** Mirror each command as `mempenny-<name>.md` in `.opencode/commands/`. User types `/mempenny-clean` on opencode, `/mempenny:clean` on Claude Code. Same command, two namespaces.

**Open question for Marcelo (Q1):** Should we *also* try `.opencode/commands/mempenny/clean.md` to see if opencode resolves it to `/mempenny/clean`? The [commands doc](https://opencode.ai/docs/commands/) only shows flat examples. Worth a 2-minute probe before committing to `mempenny-clean`.

### 1.3 Hook replacement — `SessionStart` bash → TS `session.created`

**Gap:** `hooks/nap-check.sh` (91 lines) runs on Claude Code's `SessionStart` event and emits `hookSpecificOutput.additionalContext` JSON to nudge the model toward `/mempenny:clean --yes`. Opencode has no `SessionStart` event and no bash-hook mechanism — its hooks are JS/TS plugin functions subscribing to events like `session.created`.

**Fix:** Port the script's logic verbatim to a TS plugin. The script is already a clean, defensive, pure function of `CLAUDE_PROJECT_DIR` + config → decision. The TS version:

- Subscribes to `session.created`.
- Reuses the slug rule from `CLAUDE_PROJECT_DIR` equivalent (see 1.4).
- Reads the same config, same schedule fields, same state file.
- On due: emits a toast/notification OR invokes the command via the SDK (TBD — see Q2).

Skeleton:

```ts
// .opencode/plugins/mempenny-nap.ts
import type { Plugin } from "@opencode-ai/plugin"
import { readFileSync, existsSync, mkdirSync, writeFileSync } from "node:fs"
import { homedir } from "node:os"
import { join } from "node:path"

const slug = (dir: string) => dir.replace(/\//g, "-").replace(/^-/, "")
const memoryDir = (projectDir: string) =>
  join(homedir(), ".claude", "projects", slug(projectDir), "memory")

export const MemPennyNap: Plugin = async ({ client, $, directory }) => {
  return {
    "session.created": async (input, output) => {
      try {
        const dir = process.cwd?.() ?? directory
        const memDir = memoryDir(dir)
        if (!existsSync(memDir)) return
        // … port the case statement + time gate from hooks/nap-check.sh …
        // On due:
        await client.app.log({ body: { service: "mempenny-nap", level: "info", message: `nap due for ${memDir}` } })
        // Either invoke /mempenny-clean --yes via client SDK, or emit a toast
        // pointing the user at it. (Q2.)
      } catch {
        // Defensive: a broken hook MUST NOT block session start — mirrors
        // the `|| exit 0` discipline of the original bash script.
      }
    },
  }
}
```

**Open question for Marcelo (Q2):** Does opencode's `session.created` plugin event support injecting a system-reminder (the way Claude Code's `additionalContext` does)? If yes, port directly. If no, fall back to: (a) emit a `tui.toast.show`, or (b) auto-invoke `/mempenny-clean --yes` via the SDK with the user's pre-approved nap consent. (b) most closely matches Claude behavior but is more intrusive.

### 1.4 Env vars — `CLAUDE_PLUGIN_ROOT`, `CLAUDE_PROJECT_DIR`, `CLAUDE_PLUGIN_DATA`

**Gap:** Commands and the hook read three Claude Code-provided env vars. Opencode does not set them.

| Var | Used in | Opencode equivalent |
|---|---|---|
| `CLAUDE_PLUGIN_ROOT` | Locales path in `commands/clean.md` line 27 | Resolve from `import.meta.url` in a small TS shim, OR define `MEMPENNY_ROOT` and have install script set both |
| `CLAUDE_PROJECT_DIR` | `hooks/nap-check.sh:9`, slug derivation | `process.cwd()` from TS; or a TS plugin that injects it into `shell.env` so the markdown command's bash blocks can read it |
| `CLAUDE_PLUGIN_DATA` | `hooks/nap-check.sh:43`, state file dir | `~/.local/share/mempenny` (XDG) or `~/.config/opencode/data/mempenny` |

**Fix:** Ship `.opencode/plugins/mempenny-env.ts` that injects these three vars via the [`shell.env` hook](https://opencode.ai/docs/plugins/#inject-environment-variables) so all bash blocks in command markdown keep working without rewrites:

```ts
// .opencode/plugins/mempenny-env.ts
import type { Plugin } from "@opencode-ai/plugin"
import { homedir } from "node:os"
import { join } from "node:path"

const ROOT = import.meta.dir  // plugin file's directory → .opencode/plugins/

export const MemPennyEnv: Plugin = async () => {
  return {
    "shell.env": async (input, output) => {
      output.env.CLAUDE_PLUGIN_ROOT = join(ROOT, "..", "..") // repo root
      output.env.CLAUDE_PROJECT_DIR = input.cwd
      output.env.CLAUDE_PLUGIN_DATA = join(homedir(), ".local", "share", "mempenny")
      output.env.MEMPENNY_HOST = "opencode"
    },
  }
}
```

With this shim, the existing `commands/*.md` files (copied to `.opencode/commands/`) need **zero bash-block changes** for env-var reasons. Big win.

### 1.5 Config path — `~/.claude/mempenny.config.json`

**Gap:** Hardcoded in `commands/clean.md` (line 217) and `hooks/nap-check.sh` (line 25). Opencode users may not have a `~/.claude/` dir at all.

**Fix:** Host-aware path resolution. Logic:

1. If `MEMPENNY_CONFIG_PATH` env var is set → use it (escape hatch for tests).
2. Else if `MEMPENNY_HOST=opencode` → `~/.config/opencode/mempenny.config.json`.
3. Else → `~/.claude/mempenny.config.json` (current behavior, unchanged for Claude Code).

**Migration concern:** A user who runs both hosts on the same machine would get two configs. That's actually fine — each host's config maps its own memory dirs to backup folders. But document it. Alternatively, add a `MEMPENNY_CONFIG_PATH` symlink convention; defer.

### 1.6 Memory dir auto-resolution — keep the slug rule

**Gap:** `commands/clean.md` line 43 says "auto-detect `~/.claude/projects/<project-id>/memory/` from the current project's working directory mapping." This assumes Claude Code populated that dir. Opencode doesn't populate it.

**Fix:** **Keep the slug rule as-is** — `sed 's|/|-|g; s|^-||'`. From opencode's cwd `/mnt/data/myproject`, the rule produces `-mnt-data-myproject`, and `~/.claude/projects/-mnt-data-myproject/memory/` exists because Claude Code sessions in the same project put it there. **This is the single biggest unblock:** opencode becomes a read/clean/restore client on Claude-authored memory, with zero setup. Already verified empirically — the dir exists.

If the auto-resolved path doesn't exist, fall back to `--dir` prompt as today. No new logic, just confirmation that the existing rule keeps working cross-host.

### 1.7 Auto-memory enable offer — Claude-specific

**Gap:** `commands/clean.md` Step 3 has a long subroutine that detects `~/.claude/settings.json` → `autoMemoryEnabled` and offers to flip it on. Opencode has no equivalent feature.

**Fix:** Gate the entire subroutine on `MEMPENNY_HOST != "opencode"`. On opencode, skip detection, skip the offer, set `auto_memory_now_on=false`, suppress the empty-dir signal. Concretely: insert one branch at the top of the auto-memory detection block:

```
If $MEMPENNY_HOST == "opencode":
    set auto_memory_now_on=false
    skip to next step
```

Document in README that auto-memory is a Claude Code feature; opencode users manage memory loading via `opencode.json` → `instructions`.

### 1.8 Subagent invocation syntax

**Gap:** `commands/clean.md` (and others) spawn subagents with `subagent_type: Explore`, `subagent_type: general-purpose`, `model: sonnet`, `run_in_background: false`. These are Claude Code's Task-tool conventions. Opencode's Task tool takes `subagent_type: "explore"` / `"general"` (lowercase, slightly different names) and `description` + `prompt` instead of inline prompt.

**Fix:** Translate at command-mirror time. Either:

- (a) Maintain two prompt variants per command (Claude shape, opencode shape) — duplication, but each is tuned to its host's tool.
- (b) Use neutral phrasing in a single source and let the host infer: "delegate this triage to a read-only Explore subagent" → host-specific Task call.

**Recommendation (a) for v1.2.** The prompts are 4,000 lines of careful engineering — a generic phrasing risks losing signal. Mirror the file, change only the subagent-spawn blocks. Adds a maintenance burden but keeps each host's prompt maximally effective. Track the duplication in a `CONTRIBUTING.md` "when editing commands, edit both copies" note.

**Open question for Marcelo (Q3):** (a) duplicate-and-tune, or (b) single-source-with-neutral-phrasing? Pick before implementation.

### 1.9 Install path

**Gap:** Claude users do `/plugin marketplace add`. Opencode users have no equivalent.

**Fix:** Ship `install/opencode.sh`:

```bash
#!/usr/bin/env bash
# MemPenny — opencode installer
# Usage: curl -fsSL https://raw.githubusercontent.com/marcelopaniza/mempenny/main/install/opencode.sh | bash
# Or:   git clone https://github.com/marcelopaniza/mempenny && ./mempenny/install/opencode.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OC_ROOT="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}"
mkdir -p "$OC_ROOT/commands" "$OC_ROOT/plugins"

# Symlink commands so updates to the repo flow through.
for cmd in "$REPO_ROOT"/.opencode/commands/*.md; do
  name=$(basename "$cmd")
  ln -sf "$cmd" "$OC_ROOT/commands/$name"
done

# Symlink plugins.
for plug in "$REPO_ROOT"/.opencode/plugins/*.ts; do
  name=$(basename "$plug")
  ln -sf "$plug" "$OC_ROOT/plugins/$name"
done

# Skill is auto-discovered at ~/.claude/skills/ — no install needed if user has Claude.
# For opencode-only users, symlink it into the opencode skills path.
mkdir -p "$OC_ROOT/skills"
ln -sf "$REPO_ROOT/skills/memory-hygiene" "$OC_ROOT/skills/memory-hygiene"

echo "MemPenny installed to opencode. Restart opencode to load."
echo "Commands: /mempenny-clean, /mempenny-nap, /mempenny-restore, /mempenny-memory-*"
```

Also add an `Uninstall` section.

### 1.10 Discoverability

**Gap:** README install section is Claude-only.

**Fix:** README additions (see §7 below).

---

## Axis 2 — Model compat: gap-by-gap

The prompts work on Claude because they were tuned on Claude. GLM (and GPT, Gemini) trip on three classes of thing.

### 2.1 Tool-name references — abstract to outcomes

**Gap:** Prompts reference Claude Code tools by name: "use the Read tool," "use the Write tool with X," "use AskUserQuestion with options…". These names happen to match opencode's tool names *today* (Read, Write, Bash, AskUserQuestion all exist in both), but other hosts may differ, and the implication-based phrasing ("you'll need…") relies on Claude's instruction-following.

**Fix:** Rephrase key instructions in **outcome-language**: "create a file at `<path>` with this content, backing up first" instead of "use the Write tool to…". The host translates the outcome to whatever tool it has. Keep tool names where they're unambiguous (Read/Write/Bash are near-universal), but never rely on implication alone.

**Scope:** Audit pass over `.opencode/commands/*.md` only. The Claude `commands/*.md` stays as-is (it works).

### 2.2 Loose output specs — add strict schemas

**Gap:** Claude follows implication ("respond with a markdown table"). GLM follows explicit schema. Loose specs cause format drift on weaker-instruction-following models, which breaks downstream parsing in `memory-apply`.

**Fix:** Add an explicit **Output format** block to every command that emits structured output (triage table, distillation result, migration SOURCE MAP). Example for `memory-triage`:

```
### Output format — STRICT

Respond with EXACTLY a markdown table and nothing else. No prose before or after.

| file | action | confidence | reason |
|---|---|---|---|
| feedback_foo.md | KEEP | high | still referenced in pending.md |
| project_old.md | ARCHIVE | high | superseded by project_newer.md |

- `action` MUST be one of: KEEP, DELETE, ARCHIVE, DISTILL, DEDUPE, MERGE, FLAG.
- `confidence` MUST be one of: high, medium, low.
- `reason` MUST be ≤120 chars.
- First and last characters of your response MUST be `|` and `|` respectively.
```

Claude doesn't suffer from the strictness; GLM's reliability measurably improves.

### 2.3 Distillation voice

**Gap:** `commands/memory-distill.md` produces Claude-voiced distillations. On GLM the same prompt may produce drier or more verbose output.

**Fix:** Audit `distill_output_instruction` strings in `locales/{en,es,pt-BR}/strings.json`. Tighten with concrete style examples ("`MAX 2 lines. Third-person. No marketing words.`"). Add 1-2 reference examples per locale.

### 2.4 Cross-model test harness

**Gap:** `tests/fixtures/v09/` has fixtures but no per-model expected-output harness. There's no CI signal when a prompt change regresses distillation quality on GLM specifically.

**Fix:** Extend `tests/`:

```
tests/
  fixtures/v09/...             # existing
  expected/
    sonnet/                    # per-model expected outputs
    glm-4.6/
    gpt-5/
    gemini-2.5/
  run-cross-model.sh           # runs triage on fixtures using each model, diffs vs expected/
```

Document a supported-models matrix. Set a minimum capability bar: "models must score ≥X on the triage fixture to be 'supported'."

**Open question for Marcelo (Q4):** What's the bar? "Doesn't lose content" is non-negotiable (conservation). "Distillation quality" is subjective. Suggest: bar = conservation + action-classification F1 ≥ 0.85 on the v09 fixture.

### 2.5 Hardcoded `model: sonnet` in subagent specs

**Gap:** `commands/clean.md` line 452 and elsewhere spawn subagents with `model: sonnet`. Opencode model IDs are provider-prefixed (`anthropic/claude-3-5-sonnet-...`, `zai-coding-plan/glm-5.2`, etc.).

**Fix:** Make the triage model configurable:

- Add `triage_model` field to config schema (default: inherit host's current model).
- In command prompts: `model: ${MEMPENNY_TRIAGE_MODEL}` and let the env shim resolve it.
- Document recommended models per host.

---

## Design principle: TS for deterministic, prompt for judgment

**Adopted in this PR for the new `.opencode/` layer only** (Claude `commands/` unchanged).

Move deterministic file operations — backup creation, file moves, line-count verification, conservation-check script — out of the prompt and into a TS helper module (`.opencode/plugins/mempenny-apply.ts` exposing custom tools). The model emits a JSON plan; the plugin applies it atomically and reports success/failure.

**Why:** On GLM, file-handling bugs from prompt-driven tool use are the most common failure mode (wrong path, partial write, missed backup). TS invariants can't be broken by prompt misunderstanding. Benefits every model, not just GLM.

**Scope:** v1.2 ships a minimal version — backup + verify helpers only. Full apply-layer is v1.3 alongside the auto-memory tool.

Skeleton:

```ts
// .opencode/plugins/mempenny-apply.ts
import { type Plugin, tool } from "@opencode-ai/plugin"
import { createHash } from "node:crypto"
import { cpSync, existsSync, readFileSync, readdirSync, statSync } from "node:fs"

const sha256 = (path: string) =>
  createHash("sha256").update(readFileSync(path)).digest("hex")

export const MemPennyApply: Plugin = async (ctx) => {
  return {
    tool: {
      "mempenny-backup": tool({
        description: "Create a timestamped backup of a memory directory. Returns the backup path and a SHA256 manifest.",
        args: { memory_dir: tool.schema.string() },
        async execute(args) {
          const ts = new Date().toISOString().replace(/[-:T]/g, "").slice(0, 14)
          const pid = process.pid
          const backup = `${args.memory_dir}.backups/memory.backup-${ts}-${pid}`
          cpSync(args.memory_dir, backup, { recursive: true })
          const manifest = readdirSync(args.memory_dir)
            .filter(f => f.endsWith(".md"))
            .map(f => ({ file: f, sha: sha256(`${args.memory_dir}/${f}`) }))
          return { backup, manifest }
        },
      }),
      "mempenny-verify-conservation": tool({
        description: "Verify every file in `old_files` is accounted for in `new_files` (by content hash). Used after migration.",
        args: {
          old_files: tool.schema.array(tool.schema.string()),
          new_files: tool.schema.array(tool.schema.string()),
        },
        async execute(args) {
          // … return { ok: boolean, missing: string[] }
        },
      }),
    },
  }
}
```

---

## Implementation plan — file-by-file

Ordered for reviewability. Each item = one commit.

### Commit 1 — `.opencode/` scaffolding + env shim

- `.opencode/plugins/mempenny-env.ts` — env-var injection (§1.4).
- `.opencode/plugins/mempenny-apply.ts` — backup + verify helpers (§design principle).
- Smoke test: load both plugins in opencode, verify env vars propagate to a bash block.

### Commit 2 — Command mirrors (the bulk)

- `.opencode/commands/mempenny-*.md` × 8 — copy from `commands/*.md` with:
  - Filename rename (`clean.md` → `mempenny-clean.md`).
  - `description` and `argument-hint` frontmatter preserved (opencode accepts both).
  - Auto-memory enable subroutine gated on `MEMPENNY_HOST != "opencode"` (§1.7).
  - Subagent invocation syntax adapted (§1.8 — pending Q3 decision).
  - Output-format blocks added where structured output is emitted (§2.2).
  - `~/.claude/mempenny.config.json` → host-aware path (§1.5).

### Commit 3 — Nap plugin

- `.opencode/plugins/mempenny-nap.ts` — TS port of `hooks/nap-check.sh` (§1.3).
- Pending Q2 decision on inject-vs-toast-vs-auto-invoke.

### Commit 4 — Install script + skill install

- `install/opencode.sh` (§1.9).
- `install/uninstall-opencode.sh`.

### Commit 5 — Cross-model test harness

- `tests/expected/{sonnet,glm-4.6,gpt-5,gemini-2.5}/`.
- `tests/run-cross-model.sh`.

### Commit 6 — README + docs

- README: badges update (platform: `Claude Code · opencode`), new "Install on opencode" section, new "Supported models" matrix section.
- `docs/advanced.md`: append "OpenCode differences" section.
- `docs/host-and-model-compat.md`: new, full matrix and design rationale.

### Commit 7 — CHANGELOG + version bump

- Bump `1.1.6` → `1.2.0` in `.claude-plugin/plugin.json`.
- CHANGELOG entry.

---

## Test plan

### Host compat (opencode)

On a clean opencode install, in a project with a Claude-populated `~/.claude/projects/<slug>/memory/`:

1. Run `install/opencode.sh` — expect: commands appear as `/mempenny-*`, plugins load.
2. `/mempenny-clean` — expect: auto-resolves to the same memory dir Claude uses, triages, applies with backup, restores work.
3. `/mempenny-nap --list` then schedule, restart opencode — expect: nap plugin fires `session.created`, decision matches `hooks/nap-check.sh` byte-for-byte on the same inputs.
4. `/mempenny-restore` — expect: rollback works.
5. Verify Claude Code path is untouched: reinstall plugin, run `/mempenny:clean` — expect: identical behavior to v1.1.6.

### Model compat (GLM)

On opencode running `zai-coding-plan/glm-5.2` (or whatever GLM model is current):

6. `/mempenny-clean` on the v09 fixture dir — expect: conservation check passes, action classifications match Sonnet's output ≥85%.
7. `/mempenny-memory-distill` on a verbose fixture — expect: output ≤2 lines, no content loss.
8. Run `tests/run-cross-model.sh` — expect: all four model dirs pass conservation; quality scores in `tests/expected/<model>/README.md`.

### Regression (Claude)

9. Full existing `tests/` suite passes unchanged on Claude Sonnet.
10. Existing users on v1.1.6 upgrade to v1.2.0 — no settings migration, no behavior change.

---

## Versioning & semver

- **v1.2.0** — new minor. Locked surface from v1.0+ (`docs/advanced.md` §"Locked surface") is preserved:
  - Command names and arg shapes — Claude Code names unchanged; opencode names are *additions*, not renames.
  - Config schema v2 — unchanged (the `triage_model` field is additive).
  - Backup format — unchanged.
  - Locale keys — unchanged (new keys allowed; existing preserved).
  - Lock conventions — unchanged.
- Migration: none required. Existing v1.1.6 configs work as-is on both hosts.

---

## Documentation changes (README + docs)

### README diff sketch

Add after the existing Install section:

```markdown
## Install on opencode

MemPenny also runs on [opencode](https://opencode.ai).

```bash
curl -fsSL https://raw.githubusercontent.com/marcelopaniza/mempenny/main/install/opencode.sh | bash
```

Commands are namespaced as `/mempenny-clean`, `/mempenny-nap`, `/mempenny-restore`, `/mempenny-memory-*` (hyphen, not colon — opencode filename convention).

Auto-memory (the feature that writes memory files during conversation) is Claude Code-specific. On opencode, MemPenny manages memory that was authored elsewhere — typically a Claude Code session in the same project. The two hosts share the same memory directory automatically.

## Supported hosts and models

| Host | Status |
|---|---|
| Claude Code | Full (incl. auto-memory authoring) |
| opencode | Full (clean / restore / nap); no auto-memory authoring |

| Model | Triage | Distillation | Notes |
|---|:---:|:---:|---|
| Claude Sonnet 4.5+ | ✅ | ✅ | Reference |
| Claude Opus | ✅ | ✅ | |
| GLM 4.6+ (Coder) | ✅ | ✅ | Use strict output schemas (default) |
| GPT-5 / GPT-5-Codex | ✅ | ✅ | |
| Gemini 2.5 Pro | ✅ | ⚠️ | Distillation can be verbose; review recommended |

Models must pass the [cross-model test harness](tests/run-cross-model.sh): conservation is non-negotiable; classification F1 ≥ 0.85.
```

Update badges: `platform-Claude%20Code-orange` → `platform-Claude%20Code%20·%20opencode-orange`.

---

## Open questions for Marcelo

- **Q1** — Probe nested opencode commands (`/mempenny/clean`) vs flat (`/mempenny-clean`)?
- **Q2** — Nap plugin delivery: inject system-reminder (Claude-style), toast, or auto-invoke via SDK?
- **Q3** — Subagent prompts: duplicate-and-tune per host (a), or single-source with neutral phrasing (b)?
- **Q4** — Cross-model bar: conservation + classification F1 ≥ 0.85 acceptable?
- **Q5** — Config path on opencode: separate `~/.config/opencode/mempenny.config.json`, or share `~/.claude/mempenny.config.json` for users running both hosts? (Recommendation: separate, with a one-line doc note.)

---

## Out of scope (future PRs)

- **opencode auto-memory authoring tool.** A TS plugin exposing a `memory({name, description, type, content})` custom tool so opencode sessions can write memories without Claude Code in the loop. Tracked for v1.3.
- **Heuristic auto-capture** via `session.idle` hook suggesting memory writes. Research.
- **opencode `experimental.session.compacting` integration** — inject `pending.md` + `traps.md` into compaction context. Claude has no equivalent; this would be an opencode-only feature. Tracked for v1.3.
- **Full TS apply-layer** — move all deterministic file ops out of prompts. v1.3.
- **Additional locales.**

---

## Appendix — files touched

| Path | Action |
|---|---|
| `.opencode/commands/mempenny-clean.md` | NEW (mirror of `commands/clean.md`) |
| `.opencode/commands/mempenny-nap.md` | NEW |
| `.opencode/commands/mempenny-restore.md` | NEW |
| `.opencode/commands/mempenny-memory-triage.md` | NEW |
| `.opencode/commands/mempenny-memory-apply.md` | NEW |
| `.opencode/commands/mempenny-memory-distill.md` | NEW |
| `.opencode/commands/mempenny-memory-curate.md` | NEW |
| `.opencode/commands/mempenny-memory-shard-roll.md` | NEW |
| `.opencode/plugins/mempenny-env.ts` | NEW |
| `.opencode/plugins/mempenny-nap.ts` | NEW |
| `.opencode/plugins/mempenny-apply.ts` | NEW (minimal — backup + verify helpers only) |
| `install/opencode.sh` | NEW |
| `install/uninstall-opencode.sh` | NEW |
| `tests/expected/{sonnet,glm-4.6,gpt-5,gemini-2.5}/` | NEW |
| `tests/run-cross-model.sh` | NEW |
| `docs/host-and-model-compat.md` | NEW |
| `docs/advanced.md` | EDIT (append opencode section) |
| `README.md` | EDIT (badges, install, supported models) |
| `.claude-plugin/plugin.json` | EDIT (version bump only) |
| `CHANGELOG.md` | EDIT (v1.2.0 entry) |
| `commands/*.md` | UNCHANGED |
| `hooks/*` | UNCHANGED |
| `.claude-plugin/marketplace.json` | UNCHANGED |
| `locales/*` | UNCHANGED |
| `skills/memory-hygiene/SKILL.md` | UNCHANGED (already portable) |
