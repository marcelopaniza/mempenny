#!/usr/bin/env bash
# MemPenny nap-check — SessionStart hook.
# Decides whether to nudge the model to invoke /mempenny:clean.
# Defensive by design: a broken hook MUST NOT block session start —
# every potentially-failing step ends with `|| exit 0` (silent skip).

set -uo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-}"
[ -n "$PROJECT_DIR" ] || exit 0

# Project ID encoding: Claude Code's convention (replace / with -, strip leading -)
PROJECT_ID=$(echo "$PROJECT_DIR" | sed 's|/|-|g; s|^-||')
MEMORY_DIR="$HOME/.claude/projects/$PROJECT_ID/memory"

[ -d "$MEMORY_DIR" ] || exit 0
[ ! -L "$MEMORY_DIR" ] || exit 0

MEMORY_DIR=$(realpath "$MEMORY_DIR" 2>/dev/null) || exit 0

# Defense-in-depth path-safety check — only emit paths matching MemPenny's C1 regex
# (mirrors the regex used in commands/clean.md and commands/nap.md)
[[ "$MEMORY_DIR" =~ ^/[A-Za-z0-9/_.\-\ ]{1,4096}$ ]] || exit 0

CONFIG="$HOME/.claude/mempenny.config.json"
[ -f "$CONFIG" ] || exit 0
[ ! -L "$CONFIG" ] || exit 0   # F-M2: never read a symlink config

command -v jq >/dev/null 2>&1 || exit 0

FREQUENCY=$(jq -r --arg dir "$MEMORY_DIR" '.schedules[$dir].frequency // empty' "$CONFIG" 2>/dev/null)
TIME=$(jq -r --arg dir "$MEMORY_DIR" '.schedules[$dir].time // empty' "$CONFIG" 2>/dev/null)

[ -n "$FREQUENCY" ] && [ -n "$TIME" ] || exit 0

case "$FREQUENCY" in
  daily|weekly|once) ;;
  *) exit 0 ;;
esac

[[ "$TIME" =~ ^([01]?[0-9]|2[0-3]):[0-5][0-9]$ ]] || exit 0

PLUGIN_DATA="${CLAUDE_PLUGIN_DATA:-$HOME/.claude/data/mempenny}"
# Defense-in-depth path-safety on plugin data dir (mirrors C1 regex)
[[ "$PLUGIN_DATA" =~ ^/[A-Za-z0-9/_.\-\ ]{1,4096}$ ]] || exit 0
mkdir -p "$PLUGIN_DATA" 2>/dev/null || exit 0

DIR_HASH=$(echo -n "$MEMORY_DIR" | sha1sum | cut -c1-12)
STATE_FILE="$PLUGIN_DATA/nap-$DIR_HASH.last"

LAST=""
[ -r "$STATE_FILE" ] && LAST=$(cat "$STATE_FILE" 2>/dev/null || echo "")
TODAY=$(date +%Y-%m-%d)

case "$FREQUENCY" in
  once)
    # Fire exactly once: if state file has any content, never fire again.
    [ -z "$LAST" ] || exit 0
    ;;
  daily)
    # Fire once per calendar day.
    [ "$LAST" != "$TODAY" ] || exit 0
    ;;
  weekly)
    # Fire if at least 7 days have passed since last fire.
    if [ -n "$LAST" ]; then
      LAST_EPOCH=$(date -d "$LAST" +%s 2>/dev/null || echo 0)
      TODAY_EPOCH=$(date -d "$TODAY" +%s 2>/dev/null || echo 0)
      DIFF_DAYS=$(( (TODAY_EPOCH - LAST_EPOCH) / 86400 ))
      [ "$DIFF_DAYS" -ge 7 ] || exit 0
    fi
    ;;
esac

# Time gate: only fire after the scheduled time today (lexicographic compare on HH:MM).
NOW_HHMM=$(date +%H:%M)
[[ "$NOW_HHMM" > "$TIME" || "$NOW_HHMM" == "$TIME" ]] || exit 0

# All checks passed — record the fire and emit the JSON system reminder.
echo "$TODAY" > "$STATE_FILE" || exit 0
chmod 600 "$STATE_FILE" 2>/dev/null || exit 0

# Build the additionalContext string in shell, then let jq construct the JSON
# safely. jq -n --arg performs proper JSON string escaping (quotes, backslashes,
# control chars) — defense in depth even though all interpolated values have
# already been C1-regex-validated above.
ADDITIONAL_CONTEXT="MemPenny nap is due (scheduled $FREQUENCY at $TIME, local time). Please invoke /mempenny:clean now to process the memory directory $MEMORY_DIR. After /clean completes, suggest the user restart Claude Code (Ctrl+D, then claude again) so this session loads the freshened memory state."

jq -nc \
  --arg ctx "$ADDITIONAL_CONTEXT" \
  '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}' || exit 0
