# Roadmap — what is pending

Living list of known-pending work, in priority order. Each item carries the
evidence that put it here, so a future session (or a different AI) can pick
it up cold. Shipped items move to the [CHANGELOG](../CHANGELOG.md).

## 1. Port the scheduled nap to Gemini CLI and Codex CLI

The README's rationale ("the scheduled nap runs only on Claude Code and
opencode — it's a lifecycle hook, and these hosts have no equivalent") was
true when the host matrix was researched (July 2026) and is now stale —
verified 2026-08-19:

- **Gemini CLI** shipped hooks in v0.26.0 (2026-01-28): ~a dozen lifecycle
  events including session start, plain bash scripts, and — the clean part —
  **extensions can ship hooks in their own config layer**, so
  `gemini-extension.json`'s package can carry the nap hook directly.
  Sources: <https://developers.googleblog.com/tailor-gemini-cli-to-your-workflow-with-hooks/>,
  <https://geminicli.com/docs/hooks/>,
  <https://github.com/google-gemini/gemini-cli/blob/main/docs/extensions/writing-extensions.md>
- **Codex CLI** now has a Claude-style hooks system including
  **SessionStart**, configured in the *user's* `config.toml` behind
  `[features] codex_hooks = true` — a plugin cannot ship it, so the port is
  an install-time snippet (documented step or installer script), not a
  manifest entry. Sources: <https://developers.openai.com/codex/hooks>,
  <https://github.com/openai/codex/blob/main/docs/config.md>

Port shape (mirrors the opencode notify-only nap): session-start hook runs
`hooks/nap-check.sh` against the shared memory directory (`AGENTS.md`
"Where the memory lives"); when a nap is due, inject context / notify
pointing at the host's clean flow. Gemini first (extension-shipped, zero
user setup), Codex second (config snippet + feature flag caveat).
**Includes**: reword the README rationale + flip the nap column for the
ported hosts, and update `docs/host-and-model-compat.md` (the "no
equivalent" paragraph). Target: v1.7.0.

## 2. Shard-roll engine ↔ command unification (carried since v1.5.0)

`hooks/shard-roll.sh` (the deterministic year/month/day roller) is still
standalone: `/mempenny-memory-shard-roll` closes finished years with its own
month-heading logic and does not read the day-heading layout the v1.5.0
mover writes. Unify: command invokes the engine; one day/month layout across
mover, command, and `docs/memory-taxonomy-design.md`.

## 3. opencode nap auto-invoke

On opencode the scheduled nap fires a desktop notification pointing at
`/mempenny-clean`; auto-invoke is reserved for a future release (README,
"Supported hosts & models"). Revisit when opencode's plugin API can start a
command turn safely.
