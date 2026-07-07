#!/usr/bin/env bash
# mempenny deterministic migration move (Phase B) — RELOCATE-WITH-CAT, not LLM.
#
# Reads a whole-file placement plan (JSON: [{"file":..., "topic":...}, ...]) and
# relocates each source file VERBATIM into its target topic file (frontmatter +
# a per-source heading + the file's bytes via `cat`). The LLM is never in the
# content path, so there is nothing to summarize -> conservation is structural.
#
# This script WRITES the topic files (+ the new MEMORY.md index). It does NOT
# delete the old source files — a separate commit step does that, AFTER the
# conservation check passes (verify before delete).
#
# Resumable: the plan is produced once by Phase A and saved to disk; this script
# is idempotent in the sense that re-running it from the plan rebuilds the topic
# files deterministically (it refuses to overwrite an existing topic file, so a
# partial prior run must be cleaned up first — the orchestrator deletes any
# leftover topic files before invoking this).
#
# Usage: migrate-move.sh <MEMORY_DIR> <PLAN_PATH>
#stdout:  "MOVE OK: <N> topic file(s) written" on success
#stdout:  "MOVE FAILED: <reason>" + exit 1 on any precondition failure

set -euo pipefail

MEMORY_DIR="${1:?usage: migrate-move.sh <MEMORY_DIR> <PLAN_PATH>}"
PLAN_PATH="${2:?usage: migrate-move.sh <MEMORY_DIR> <PLAN_PATH>}"

C1='^/[A-Za-z0-9/_.\ -]{1,4096}$'
H1='^[A-Za-z0-9][A-Za-z0-9_.\-]*\.md$'
RESERVED="charter pending worklog support traps rules decisions reference"

fail() { echo "MOVE FAILED: $*"; exit 1; }

# --- path + environment validation (C1, F-M2) ---
[[ "$MEMORY_DIR" =~ $C1 ]] || fail "MEMORY_DIR fails C1"
[[ "$PLAN_PATH"  =~ $C1 ]] || fail "PLAN_PATH fails C1"
[ -d "$MEMORY_DIR" ] || fail "MEMORY_DIR does not exist"
[ ! -L "$MEMORY_DIR" ] || fail "MEMORY_DIR is a symlink (F-M2)"
[ -f "$PLAN_PATH" ] || fail "PLAN_PATH does not exist"
[ ! -L "$PLAN_PATH" ] || fail "PLAN_PATH is a symlink (F-M2)"
command -v jq >/dev/null 2>&1 || fail "jq not installed"

# --- validate every entry before touching anything (fail closed) ---
n=$(jq '. | length' "$PLAN_PATH")
[ "$n" -gt 0 ] || fail "plan is empty"
seen_files=""
for i in $(seq 0 $((n-1))); do
    f=$(jq -r ".[$i].file"  "$PLAN_PATH")
    t=$(jq -r ".[$i].topic" "$PLAN_PATH")
    [[ "$f" =~ $H1 ]] || fail "entry $i file fails H1: $f"
    case " $RESERVED " in *" $t "*) ;; *) fail "entry $i topic not one of the 8 reserved: $t" ;; esac
    [ -f "$MEMORY_DIR/$f" ] || fail "source file missing: $f"
    [ ! -L "$MEMORY_DIR/$f" ] || fail "source file is a symlink (F-M2): $f"
    case "$seen_files" in *" $f "*) fail "duplicate file in plan: $f" ;; esac
    seen_files="$seen_files $f "
    [ ! -e "$MEMORY_DIR/$t.md" ] || fail "topic file already exists (collision): $t.md"
done

# --- determine which topics are present, emitted in reserved order ---
topics_present=""
for t in $RESERVED; do
    jq -e --arg t "$t" 'map(select(.topic == $t)) | length > 0' "$PLAN_PATH" >/dev/null && topics_present="$topics_present $t"
done

# --- build each topic file atomically: frontmatter + per-source heading + verbatim content ---
for t in $topics_present; do
    tmp=$(mktemp "${MEMORY_DIR}/.mempenny-move-XXXXXXXX") || fail "mktemp failed"
    {
        printf -- '---\ntype: %s\n---\n\n' "$t"
        for i in $(seq 0 $((n-1))); do
            f=$(jq -r ".[$i].file"  "$PLAN_PATH")
            tt=$(jq -r ".[$i].topic" "$PLAN_PATH")
            [ "$tt" = "$t" ] || continue
            # The old MEMORY.md is the pre-migration index; its lines are conserved
            # verbatim under an explicit archive heading.
            [ "$f" = "MEMORY.md" ] && printf -- '## Archived pre-migration index\n\n'
            printf -- '### %s\n\n' "$f"
            cat "$MEMORY_DIR/$f"
            printf -- '\n\n'
        done
    } > "$tmp"
    chmod 600 "$tmp"
    mv "$tmp" "$MEMORY_DIR/$t.md"
done

# --- stage the fresh 8-topic index at a hidden path (do NOT overwrite MEMORY.md yet) ---
# Finalize installs this into MEMORY.md AFTER the conservation check passes. Installing
# it now would overwrite the old MEMORY.md before the conservation check can read it as
# an OLD_FILE (old MEMORY.md content is already conserved verbatim under the archive
# heading in reference.md above; the check compares OLD_FILES against the topic corpus).
mem_tmp=$(mktemp "${MEMORY_DIR}/.mempenny-move-XXXXXXXX") || fail "mktemp failed"
{
    printf -- '# Memory Index\n\n'
    for t in $RESERVED; do
        [ -f "$MEMORY_DIR/$t.md" ] && printf -- '- [%s.md](%s.md)\n' "$t" "$t"
    done
} > "$mem_tmp"
chmod 600 "$mem_tmp"
mv "$mem_tmp" "$MEMORY_DIR/.mempenny-new-index.md"

written=$(echo "$topics_present" | wc -w)
echo "MOVE OK: $written topic file(s) written; new index staged at .mempenny-new-index.md"
