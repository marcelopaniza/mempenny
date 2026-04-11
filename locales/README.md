# Locales

MemPenny's slash commands are instruction templates for Claude. Most of the template text is *instructions to the model* and doesn't need translation — the model follows English instructions reliably. What *does* need translation is:

1. **User-visible summary labels** — the table headers, bucket names, totals block.
2. **Distilled replacement language** — when MemPenny triages memories written in Portuguese, the distilled replacements must also be in Portuguese, not English.

Both are handled through the tiny JSON files in this directory.

## How it works

Each command accepts a `--lang <code>` argument. When set, the command:

1. Reads `${CLAUDE_PLUGIN_ROOT}/locales/<code>/strings.json` for user-visible labels.
2. Passes the `distill_output_instruction` from that file to the triage/distill subagent, telling it which language to write distilled replacements in.
3. Falls back to English (`locales/en/strings.json`) if the requested locale doesn't exist.

The locale can also be set via the `MEMPENNY_LOCALE` environment variable, so you don't have to pass `--lang` every time.

## Supported locales (v0.2)

| Code  | Language               |
|-------|------------------------|
| `en`  | English (default)      |
| `pt-BR` | Português (Brasil)   |
| `es`  | Español                |

## Adding a new locale

1. Copy `locales/en/strings.json` to `locales/<your-code>/strings.json`.
2. Translate every value. **Do not** translate keys.
3. **Preserve placeholders** like `{table_path}`, `{path}`, `{size}`, `{lang}` exactly — they're filled in at runtime.
4. Update `_meta.language`, `_meta.code`, `_meta.native_name`, and `_meta.direction`.
5. The `distill_output_instruction` field is critical: it's appended to the subagent prompt and tells the model which language to write distilled memory replacements in. Be explicit about preserving technical terms (URLs, file paths, commands, version numbers) verbatim — those should never be translated.
6. Add your code to the table above in this README.
7. Open a PR.

## Locale code convention

Use BCP 47 tags:
- Language only: `en`, `es`, `fr`, `de`, `ja`, `zh`
- Language + region when the region matters: `pt-BR`, `zh-CN`, `zh-TW`, `en-GB`

Prefer language-only codes unless there's a meaningful regional difference. `pt-BR` exists because Brazilian Portuguese differs from European Portuguese enough to matter for a Brazilian user's memory files.

## Why this is a JSON file and not a full prompt translation

The slash command files under `commands/` are mostly *instructions to Claude* — "spawn a subagent", "write the table to /tmp", "preserve YAML frontmatter". That scaffolding works fine in English regardless of the user's language. Translating the whole command file would triple the maintenance cost for near-zero user benefit.

What matters is the *output*: the triage table, the summary, and the distilled replacements. Those are what the user reads. Those are what this JSON file covers.

If you want a fully localized command file (the step-by-step instructions in the user's language too), that's a v0.3+ feature. Open an issue first so we can discuss scope.
