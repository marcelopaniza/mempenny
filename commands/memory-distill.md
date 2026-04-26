---
description: Distill a single memory file in-place — replace prose narrative with 1-3 sentences of forward-looking truth.
argument-hint: <path-to-file> [--lang <code>]
---

> **Note:** `/mempenny:memory-distill` operates on a single file via its explicit path argument, so it does not need `--dir`. The file path IS the target.

Distill a single memory file in-place. No backup — this operation is small and the user can recover from the filesystem's own history if they care.

## Step 1 — Parse arguments

The user invoked this command with: $ARGUMENTS

- **First positional argument** — absolute path to a memory file. Required.
- **`--lang <code>`** — output language for the distilled replacement and UI labels. If not passed, check `MEMPENNY_LOCALE` env var. Default `en`.

## Step 2 — Load locale strings

**2a — Validate `<lang>` before reading (H2: path traversal guard)**

Before constructing the locale path, validate that `<lang>` matches the regex `^[a-zA-Z]{2,3}(-[A-Za-z0-9]{2,8})?$`. If it does not match, treat it exactly like a missing locale: silently reset `<lang>` to `en` and warn with `errors.locale_missing`.

Read `${CLAUDE_PLUGIN_ROOT}/locales/<lang>/strings.json`. Fall back to `en` and warn with `errors.locale_missing` if missing. You need `distill.*` labels and `distill_output_instruction`.

## Step 3 — Read the target

Read the file at the given path.

If the file has YAML frontmatter (starts with `---`), separate the frontmatter block from the body. The frontmatter will be preserved exactly; only the body gets distilled.

## Step 4 — Produce the distilled replacement

Apply the locale's `distill_output_instruction` to yourself, then produce a distilled replacement that follows these rules:

- **Max 3 sentences** — hard limit
- **Forward-looking** — what's now true, not what happened
- **Factual** — no narrative, no "we decided", no "I noticed"
- **Preserve** any URLs, file paths, commands, code references, version numbers, or migration IDs mentioned in the original — **verbatim**, even if writing in a non-English locale
- **The test:** if a future Claude session reads this and nothing else, does it know what it needs to know?

If the file is already tight (≤3 sentences, already forward-looking), print `distill.already_tight_message` from the locale and stop.

If the load-bearing content genuinely cannot fit in 3 sentences without loss, print `distill.cannot_compress_message` and stop — don't ship a lossy distillation.

## Step 5 — Show the proposal

Print using locale labels:

```
{file_label}: <path>
{size_label}: <before> B → <after> B (<percentage>% {reduction_suffix})

--- {current_body_header} ---
<first 10 lines of current body>
<...>

--- {proposed_body_header} ---
<the 1-3 sentence replacement>
```

## Step 6 — Confirm and apply

Ask the user the `distill.action_prompt` question (e.g., "Apply, skip, or edit?"). Accept answers in any language — match on intent, not exact string:

- **apply** — preserve the frontmatter (if any), replace the body with the distilled text, write back with a trailing newline. Report with `distill.applied_message`, substituting `{size}`.
- **skip** — no changes. Report with `distill.skipped_message`.
- **edit** — show the proposal again, invite the user to dictate changes, produce a revised version, and ask again.

## Constraints

- Never delete the frontmatter block — preserve it character-for-character.
- Never add new content beyond what's already in the file — distillation extracts, it doesn't invent.
- If the original has multiple load-bearing facts, keep all of them; "max 3 sentences" is a compression target, not a truncation rule.
- Technical terms (URLs, paths, commands, versions) are **never** translated, even when producing Portuguese/Spanish/etc. output.
