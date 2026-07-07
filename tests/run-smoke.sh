#!/usr/bin/env bash
# MemPenny — test smoke (conservation-grade, no LLM budget required).
#
# This is the automated floor: it validates that every test fixture is
# well-formed and safe to hand to a model. The non-negotiable behavioral
# invariant — conservation (no content lost across a clean/migrate pass) —
# cannot be asserted without a live model in the loop; that procedure is
# documented at the bottom of this file and in docs/host-and-model-compat.md.
#
# Why not a full cross-model F1 harness here: see v1.2 review PT-1. A solo
# repo with no CI LLM budget ships the cheap structural check now and defers
# the per-model quality bar to v1.3 once there is real failure data to score
# against.
#
# Usage: ./tests/run-smoke.sh

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURES="$ROOT/tests/fixtures"

# C1 (path regex) and H1 (filename regex), mirrored from SECURITY.md.
C1_RE='^/[A-Za-z0-9/_.\ -]{1,4096}$'
H1_RE='^[A-Za-z0-9][A-Za-z0-9_.\-]*\.md$'

fail=0
checked=0

check_fixture() {
    local dir="$1"
    local name
    name=$(basename "$dir")
    checked=$((checked + 1))

    # Absolute path must pass C1 (otherwise the plugin would refuse it anyway).
    if ! [[ "$dir" =~ $C1_RE ]]; then
        echo "FAIL  $name — directory path fails C1: $dir"
        fail=$((fail + 1)); return
    fi

    # Safety marker present.
    if [ ! -f "$dir/.mempenny-fixture" ]; then
        echo "FAIL  $name — missing .mempenny-fixture safety marker"
        fail=$((fail + 1)); return
    fi

    # MEMORY.md index present.
    if [ ! -f "$dir/MEMORY.md" ]; then
        echo "FAIL  $name — missing MEMORY.md"
        fail=$((fail + 1)); return
    fi

    # No symlinks anywhere in the fixture (F-M2 — fixtures are static data).
    if [ -n "$(find "$dir" -type l -print -quit)" ]; then
        echo "FAIL  $name — contains a symlink (F-M2 violation)"
        fail=$((fail + 1)); return
    fi

    # Every .md filename matches H1.
    local bad=""
    while IFS= read -r f; do
        local b
        b=$(basename "$f")
        if ! [[ "$b" =~ $H1_RE ]]; then
            bad="$bad $b"
        fi
    done < <(find "$dir" -maxdepth 1 -type f -name '*.md')
    if [ -n "$bad" ]; then
        echo "FAIL  $name — non-H1 filenames:$bad"
        fail=$((fail + 1)); return
    fi

    # At least one source .md beyond MEMORY.md (else nothing to triage).
    local src_count
    src_count=$(find "$dir" -maxdepth 1 -type f -name '*.md' ! -name 'MEMORY.md' | wc -l)
    if [ "$src_count" -lt 1 ]; then
        echo "FAIL  $name — no source .md files to triage"
        fail=$((fail + 1)); return
    fi

    echo "ok    $name ($src_count source file(s))"
}

echo "MemPenny fixture smoke — structural integrity"
echo

if [ ! -d "$FIXTURES" ]; then
    echo "FAIL  no fixtures dir at $FIXTURES"
    exit 1
fi

while IFS= read -r -d '' dir; do
    [ -f "$dir/.mempenny-fixture" ] && check_fixture "$dir"
done < <(find "$FIXTURES" -mindepth 1 -type d -print0)

echo
echo "checked=$checked  failed=$fail"

if [ "$fail" -ne 0 ]; then
    exit 1
fi

cat <<'NOTE'

Structural checks passed. The behavioral invariant (conservation — no content
lost across a clean/migrate pass) requires a live model and is run manually:

  for f in tests/fixtures/v09/*/; do
    work="$(mktemp -d)"
    cp -a "$f/." "$work/"
    # then, in your host (Claude Code or opencode), run on the COPY:
    #   /mempenny:clean --dir "$work" --yes     (Claude Code)
    #   /mempenny-clean --dir "$work" --yes     (opencode)
    # conservation is asserted by the apply step's own scripted check; a failed
    # run reports MIGRATION FAILED: conservation check found <N> unaccounted lines.
  done

Run that loop under each model you support (Sonnet, GLM, GPT-5, Gemini) and
confirm every fixture reports MIGRATION APPLIED with TOTAL_EXTRA=0 (no line
dropped) and no unaccounted lines. Classification quality (F1) is deferred to
v1.3 — see docs/host-and-model-compat.md.
NOTE
exit 0
