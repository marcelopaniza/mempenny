#!/usr/bin/env bash
# MemPenny — nap-check test suite (deterministic, no LLM, no network).
#
# Exercises hooks/nap-check.sh in all three host modes (claude / gemini /
# codex) inside a sandbox $HOME, plus the host-selection guards in
# hooks/hooks.json: each hooks.json entry is executed under each host's
# simulated environment and must fire on exactly its own host, silently
# no-op elsewhere. Nothing outside the sandbox is read or written.
#
# Usage: ./tests/run-napcheck.sh

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/hooks/nap-check.sh"
HOOKSJSON="$ROOT/hooks/hooks.json"

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not installed"; exit 0; }

fail=0
checked=0

ok()   { checked=$((checked + 1)); echo "ok    $1"; }
bad()  { checked=$((checked + 1)); fail=$((fail + 1)); echo "FAIL  $1"; }

# --- sandbox ---------------------------------------------------------------
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
H="$SANDBOX/home"
PROJ="$SANDBOX/proj"
mkdir -p "$H" "$PROJ"

# Memory dir per the slug rule (leading dash kept) + a schedule that is always
# past-due today (time 00:00).
SLUG="$(echo "$PROJ" | sed 's|/|-|g')"
MEMDIR="$H/.claude/projects/$SLUG/memory"
mkdir -p "$MEMDIR"
echo "# MEMORY" > "$MEMDIR/MEMORY.md"
REAL_MEMDIR="$(HOME="$H" realpath "$MEMDIR")"
jq -n --arg dir "$REAL_MEMDIR" \
  '{version: 2, memory_dirs: {}, schedules: {($dir): {frequency: "daily", time: "00:00"}}}' \
  > "$H/.claude/mempenny.config.json"

# Run nap-check with a controlled environment. Args: extra VAR=VALUE pairs.
run_nap() {
    env -i PATH="$PATH" HOME="$H" "$@" bash "$SCRIPT" 2>/dev/null
}

# --- 1. claude mode --------------------------------------------------------
CLAUDE_DATA="$SANDBOX/claude-data"
out=$(run_nap CLAUDE_PROJECT_DIR="$PROJ" CLAUDE_PLUGIN_DATA="$CLAUDE_DATA")
if echo "$out" | jq -e '.hookSpecificOutput.hookEventName == "SessionStart"' >/dev/null 2>&1 \
   && echo "$out" | grep -q "/mempenny:clean --yes"; then
    ok "claude fires with SessionStart JSON + /mempenny:clean nudge"
else
    bad "claude fire — got: ${out:-<empty>}"
fi
[ -f "$CLAUDE_DATA/nap-$(echo -n "$REAL_MEMDIR" | sha1sum | cut -c1-12).last" ] \
    && ok "claude state file recorded (unprefixed name preserved)" \
    || bad "claude state file missing"

out=$(run_nap CLAUDE_PROJECT_DIR="$PROJ" CLAUDE_PLUGIN_DATA="$CLAUDE_DATA")
[ -z "$out" ] && ok "claude second run same day is silent" || bad "claude re-fired same day"

# --- 2. gemini mode (independent state from claude) ------------------------
GEM_DATA="$SANDBOX/gem-data"
out=$(run_nap MEMPENNY_HOST=gemini GEMINI_PROJECT_DIR="$PROJ" MEMPENNY_DATA_DIR="$GEM_DATA")
if echo "$out" | jq -e '.hookSpecificOutput.hookEventName == "SessionStart"' >/dev/null 2>&1 \
   && echo "$out" | grep -q "rules-only" && echo "$out" | grep -q "AGENTS.md"; then
    ok "gemini fires (own state, rules-only AGENTS.md nudge)"
else
    bad "gemini fire — got: ${out:-<empty>}"
fi
ls "$GEM_DATA"/nap-gemini-*.last >/dev/null 2>&1 \
    && ok "gemini state file is host-prefixed" || bad "gemini state file missing/misnamed"

# gemini also honors the CLAUDE_PROJECT_DIR compat alias
GEM_DATA2="$SANDBOX/gem-data2"
out=$(run_nap MEMPENNY_HOST=gemini CLAUDE_PROJECT_DIR="$PROJ" MEMPENNY_DATA_DIR="$GEM_DATA2")
echo "$out" | grep -q "rules-only" \
    && ok "gemini falls back to CLAUDE_PROJECT_DIR alias" || bad "gemini alias fallback"

# --- 3. codex mode (project dir from cwd) ----------------------------------
CODEX_DATA="$SANDBOX/codex-data"
out=$(cd "$PROJ" && env -i PATH="$PATH" HOME="$H" MEMPENNY_HOST=codex PLUGIN_DATA="$CODEX_DATA" bash "$SCRIPT" 2>/dev/null)
if echo "$out" | grep -q "memory-hygiene skill"; then
    ok "codex fires from cwd with skill nudge"
else
    bad "codex fire — got: ${out:-<empty>}"
fi
ls "$CODEX_DATA"/nap-codex-*.last >/dev/null 2>&1 \
    && ok "codex state file is host-prefixed under PLUGIN_DATA" || bad "codex state file missing"
out=$(cd "$PROJ" && env -i PATH="$PATH" HOME="$H" MEMPENNY_HOST=codex PLUGIN_DATA="$CODEX_DATA" bash "$SCRIPT" 2>/dev/null)
[ -z "$out" ] && ok "codex second run same day is silent" || bad "codex re-fired same day"

# --- 4. guards -------------------------------------------------------------
out=$(run_nap MEMPENNY_HOST=weird CLAUDE_PROJECT_DIR="$PROJ")
[ -z "$out" ] && ok "unknown host is a silent no-op" || bad "unknown host produced output"

mv "$H/.claude/mempenny.config.json" "$H/.claude/real.json"
ln -s "$H/.claude/real.json" "$H/.claude/mempenny.config.json"
out=$(run_nap MEMPENNY_HOST=gemini GEMINI_PROJECT_DIR="$PROJ" MEMPENNY_DATA_DIR="$SANDBOX/g3")
[ -z "$out" ] && ok "symlinked config refused (F-M2)" || bad "symlinked config was read"
rm "$H/.claude/mempenny.config.json" && mv "$H/.claude/real.json" "$H/.claude/mempenny.config.json"

out=$(run_nap MEMPENNY_HOST=gemini GEMINI_PROJECT_DIR="$PROJ" MEMPENNY_DATA_DIR="$SANDBOX/g4" MEMPENNY_CONFIG_PATH="/bad;path")
[ -z "$out" ] && ok "C1-invalid MEMPENNY_CONFIG_PATH refused" || bad "invalid config override accepted"

ALT_CFG="$SANDBOX/alt-config.json"
cp "$H/.claude/mempenny.config.json" "$ALT_CFG"
out=$(run_nap MEMPENNY_HOST=gemini GEMINI_PROJECT_DIR="$PROJ" MEMPENNY_DATA_DIR="$SANDBOX/g5" MEMPENNY_CONFIG_PATH="$ALT_CFG")
echo "$out" | grep -q "rules-only" \
    && ok "MEMPENNY_CONFIG_PATH override honored" || bad "config override not honored"

# Unpadded hand-edited hour must still fire ("0:00" is always past once padded).
jq -n --arg dir "$REAL_MEMDIR" \
  '{version: 2, memory_dirs: {}, schedules: {($dir): {frequency: "daily", time: "0:00"}}}' \
  > "$ALT_CFG"
out=$(run_nap MEMPENNY_HOST=gemini GEMINI_PROJECT_DIR="$PROJ" MEMPENNY_DATA_DIR="$SANDBOX/g7" MEMPENNY_CONFIG_PATH="$ALT_CFG")
echo "$out" | grep -q "rules-only" \
    && ok "unpadded schedule hour is normalized and fires" || bad "unpadded hour did not fire"

# Weekly with a 10-day-old last-fire must fire again.
H12="$(echo -n "$REAL_MEMDIR" | sha1sum | cut -c1-12)"
mkdir -p "$SANDBOX/g8"
date -d '-10 days' +%Y-%m-%d > "$SANDBOX/g8/nap-gemini-$H12.last"
jq -n --arg dir "$REAL_MEMDIR" \
  '{version: 2, memory_dirs: {}, schedules: {($dir): {frequency: "weekly", time: "00:00"}}}' \
  > "$ALT_CFG"
out=$(run_nap MEMPENNY_HOST=gemini GEMINI_PROJECT_DIR="$PROJ" MEMPENNY_DATA_DIR="$SANDBOX/g8" MEMPENNY_CONFIG_PATH="$ALT_CFG")
echo "$out" | grep -q "rules-only" \
    && ok "weekly fires again after 10 days" || bad "weekly did not re-fire after 10 days"

# Time gate: a schedule 2 minutes in the future must not fire (skipped in the
# minutes right before midnight, where +2min wraps to a past lexicographic
# time, or where date lacks both the GNU and BSD relative syntax).
FUTURE="$(date -d '+2 minutes' +%H:%M 2>/dev/null || date -v +2M +%H:%M 2>/dev/null || echo "")"
NOW="$(date +%H:%M)"
if [ -n "$FUTURE" ] && [[ "$FUTURE" > "$NOW" ]]; then
    jq -n --arg dir "$REAL_MEMDIR" --arg t "$FUTURE" \
      '{version: 2, memory_dirs: {}, schedules: {($dir): {frequency: "daily", time: $t}}}' \
      > "$ALT_CFG"
    out=$(run_nap MEMPENNY_HOST=gemini GEMINI_PROJECT_DIR="$PROJ" MEMPENNY_DATA_DIR="$SANDBOX/g6" MEMPENNY_CONFIG_PATH="$ALT_CFG")
    [ -z "$out" ] && ok "time gate holds before the scheduled time" || bad "fired before scheduled time"
else
    ok "time gate check skipped (too close to midnight)"
fi

# --- 5. hooks.json host-selection guard matrix -----------------------------
jq empty "$HOOKSJSON" 2>/dev/null && ok "hooks.json is valid JSON" || bad "hooks.json invalid"
n_entries=$(jq '.hooks.SessionStart[0].hooks | length' "$HOOKSJSON")
[ "$n_entries" = "3" ] && ok "hooks.json has the 3 host entries" || bad "expected 3 entries, got $n_entries"

# Simulated host environments. extensionPath is a textual substitution on real
# Gemini; exporting it as an env var reproduces the same expansion under sh.
run_entry() { # $1 = entry index, then VAR=VALUE pairs
    local idx="$1"; shift
    local cmd
    cmd=$(jq -r ".hooks.SessionStart[0].hooks[$idx].command" "$HOOKSJSON")
    ( cd "$PROJ" && env -i PATH="$PATH" HOME="$H" "$@" sh -c "$cmd" 2>/dev/null )
}

# Fresh state dirs so every expected fire actually fires.
for host in claude codex gemini; do
    for idx in 0 1 2; do
        case "$host" in
            claude) set -- CLAUDE_PLUGIN_ROOT="$ROOT" CLAUDE_PROJECT_DIR="$PROJ" CLAUDE_PLUGIN_DATA="$SANDBOX/mx-claude" ;;
            codex)  set -- PLUGIN_ROOT="$ROOT" CLAUDE_PLUGIN_ROOT="$ROOT" PLUGIN_DATA="$SANDBOX/mx-codex" ;;
            gemini) set -- GEMINI_SESSION_ID=test-123 GEMINI_PROJECT_DIR="$PROJ" extensionPath="$ROOT" MEMPENNY_DATA_DIR="$SANDBOX/mx-gemini" ;;
        esac
        out=$(run_entry "$idx" "$@")
        expected_fire=""
        [ "$host" = claude ] && [ "$idx" = 0 ] && expected_fire=1
        [ "$host" = codex ]  && [ "$idx" = 1 ] && expected_fire=1
        [ "$host" = gemini ] && [ "$idx" = 2 ] && expected_fire=1
        if [ -n "$expected_fire" ]; then
            echo "$out" | jq -e '.hookSpecificOutput.additionalContext | length > 0' >/dev/null 2>&1 \
                && ok "matrix: entry $idx fires on $host" \
                || bad "matrix: entry $idx should fire on $host — got: ${out:-<empty>}"
        else
            [ -z "$out" ] \
                && ok "matrix: entry $idx silent on $host" \
                || bad "matrix: entry $idx leaked output on $host: $out"
        fi
    done
done

# --- 6. stray-env regressions ----------------------------------------------
# A stray generic env var from an unrelated tool must not disable or misroute
# the check: entry 0 still fires on Claude with a bogus PLUGIN_ROOT exported,
# and the foreign entries' existence-checked guards keep them silent.
out=$(run_entry 0 CLAUDE_PLUGIN_ROOT="$ROOT" CLAUDE_PROJECT_DIR="$PROJ" CLAUDE_PLUGIN_DATA="$SANDBOX/stray-claude" PLUGIN_ROOT=/nonexistent)
echo "$out" | jq -e '.hookSpecificOutput.additionalContext | length > 0' >/dev/null 2>&1 \
    && ok "stray PLUGIN_ROOT does not kill the Claude entry" \
    || bad "stray PLUGIN_ROOT killed the Claude entry — got: ${out:-<empty>}"
out=$(run_entry 1 CLAUDE_PLUGIN_ROOT="$ROOT" CLAUDE_PROJECT_DIR="$PROJ" CLAUDE_PLUGIN_DATA="$SANDBOX/stray-claude" PLUGIN_ROOT=/nonexistent)
[ -z "$out" ] \
    && ok "codex entry stays silent under a bogus PLUGIN_ROOT" \
    || bad "codex entry leaked output under bogus PLUGIN_ROOT: $out"
out=$(run_entry 2 CLAUDE_PLUGIN_ROOT="$ROOT" CLAUDE_PROJECT_DIR="$PROJ" GEMINI_SESSION_ID=stray)
[ -z "$out" ] \
    && ok "gemini entry stays silent under a stray GEMINI_SESSION_ID" \
    || bad "gemini entry leaked output under stray GEMINI_SESSION_ID: $out"

echo
echo "checked=$checked  failed=$fail"
[ "$fail" -eq 0 ] || exit 1
