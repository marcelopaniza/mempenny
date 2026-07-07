#!/usr/bin/env bash
# mempenny adaptive shard-roll (v1.5).
#
# Bounds a log-topic file by rolling CLOSED periods into frozen shards, drilling
# year -> month -> day until the active file fits under <ceiling>. Requires the
# v1.5 day-structured layout (## YYYY-MM-DD headings, as produced by migrate-move.sh).
# Intra-content ## headings (e.g. "## What happened") are NOT day headings and stay
# with whatever day section they fall in.
#
# Cascade: pick the COARSEST granularity G whose active-period size fits ceiling, then
# roll everything older than the current period (at G) into shards. Active period =
# current year (G=year) / current month (G=month) / today (G=day). If today alone
# exceeds ceiling, roll nothing and tolerate (the "fingers crossed" floor).
#
# Usage: shard-roll.sh <topic-file> <ceiling-bytes>
# stdout: "SHARD-ROLL OK: <G>; rolled <N> section(s) into <K> shard(s); parent <before> -> <after> bytes"
#         or "SHARD-ROLL OK: nothing to roll (active <G> alone <size> ≤ ceiling <ceiling>)"
#         or "SHARD-ROLL FAILED: <reason>" + exit 1.

set -euo pipefail

FILE="${1:?usage: shard-roll.sh <topic-file> <ceiling-bytes>}"
CEILING="${2:?usage: shard-roll.sh <topic-file> <ceiling-bytes>}"

fail() { echo "SHARD-ROLL FAILED: $*"; exit 1; }

[[ "$FILE" =~ ^/[A-Za-z0-9/_.\ -]{1,4096}\.md$ ]] || fail "path fails C1/H1"
[ -f "$FILE" ] || fail "not a file: $FILE"
[ ! -L "$FILE" ] || fail "refusing symlink (F-M2)"
[[ "$CEILING" =~ ^[0-9]+$ ]] || fail "ceiling must be a positive integer"

DIR=$(dirname "$FILE"); STEM=$(basename "$FILE" .md)
TODAY=$(date -u +%Y-%m-%d); TY=${TODAY:0:4}; TM=${TODAY:5:2}

# Parse sections: emit "date|start|end" (1-indexed line ranges) for each day/Undated
# heading. preamble = everything before the first such heading (frontmatter etc.).
READ=$(awk '
  function emit() { if (prev != "") print prev "|" start "|" (NR - 1) }
  /^## [0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]]*$/ {
    d = substr($0, 4, 10); emit(); prev = d; start = NR; next
  }
  /^## Undated[[:space:]]*$/ { emit(); prev = "undated"; start = NR; next }
  END { emit() }
' "$FILE")
[ -n "$READ" ] || { echo "SHARD-ROLL OK: nothing to roll (no ## YYYY-MM-DD day headings — not a v1.5 log-topic file)"; exit 0; }

# First day-heading line = preamble boundary.
FIRST_START=$(printf '%s\n' "$READ" | head -1 | cut -d'|' -f2)
PREAMBLE_END=$((FIRST_START - 1))

# bytes of a line range (inclusive), including the trailing newline of each line.
range_bytes() { sed -n "${1},${2}p" "$FILE" | wc -c | tr -d ' '; }
PREAMBLE_BYTES=0
if [ "$PREAMBLE_END" -ge 1 ]; then PREAMBLE_BYTES=$(sed -n "1,${PREAMBLE_END}p" "$FILE" | wc -c | tr -d ' '); fi
TOTAL=$(wc -c < "$FILE" | tr -d ' ')

# Bucket sections: active-size per granularity + rolled mapping.
# For each section compute: date, year(yyyy), month(yyyymm), bytes, range.
active_year=0; active_month=0; active_day=0; undated_bytes=0
declare -A BY_YEAR BY_MONTH BY_DAY   # period -> "ranges" (start-end,start-end,...)
SECTION_DATES=""
while IFS='|' read -r d s e; do
    b=$(range_bytes "$s" "$e")
    rng="$s-$e"
    if [ "$d" = "undated" ]; then undated_bytes=$((undated_bytes + b)); continue; fi
    y=${d:0:4}; ym=${d:0:4}-${d:5:2}
    SECTION_DATES="$SECTION_DATES $d|$y|$ym|$s|$e|$b"
    # active accumulators
    [ "$y" = "$TY" ] && active_year=$((active_year + b))
    [ "$ym" = "$TY-$TM" ] && active_month=$((active_month + b))
    [ "$d" = "$TODAY" ] && active_day=$((active_day + b))
    # rolled candidate buckets (older than today at each granularity)
    BY_YEAR[$y]="${BY_YEAR[$y]:+${BY_YEAR[$y]},}$rng"
    BY_MONTH[$ym]="${BY_MONTH[$ym]:+${BY_MONTH[$ym]},}$rng"
    BY_DAY[$d]="${BY_DAY[$d]:+${BY_DAY[$d]},}$rng"
done <<EOF
$READ
EOF

# Overhead = preamble + a Shards index (~ small) + undated (stays). Pick coarsest G
# whose active size leaves room. Keep undated in parent always.
OVERHEAD=$((PREAMBLE_BYTES + undated_bytes + 200))   # +200 for the Shards index block
G=""
ACTIVE=0
if [ $((active_year + OVERHEAD)) -le "$CEILING" ]; then G=year; ACTIVE=$active_year
elif [ $((active_month + OVERHEAD)) -le "$CEILING" ]; then G=month; ACTIVE=$active_month
elif [ $((active_day + OVERHEAD)) -le "$CEILING" ]; then G=day; ACTIVE=$active_day
fi

# Determine rolled ranges + shard grouping for the chosen G.
declare -A SHARD_RANGES
if [ -z "$G" ]; then
    # even today alone > ceiling -> tolerate (day is the floor)
    echo "SHARD-ROLL OK: nothing to roll (today $TODAY alone ${active_day}B + overhead ${OVERHEAD}B > ceiling ${CEILING}B; tolerated at the day floor)"
    exit 0
fi

rolled_any=0   # scalar flag (not ${#SHARD_RANGES[@]} — set -u quibbles on a declared-but-empty assoc array)
case "$G" in
    year)  for period in "${!BY_YEAR[@]}"; do
             d=${period:0:4}; [ "$d" = "$TY" ] && continue   # keep current year
             SHARD_RANGES["$STEM-$period.md"]="${BY_YEAR[$period]}"; rolled_any=1
           done ;;
    month) for period in "${!BY_MONTH[@]}"; do
             [ "$period" = "$TY-$TM" ] && continue            # keep current month
             SHARD_RANGES["$STEM-$period.md"]="${BY_MONTH[$period]}"; rolled_any=1
           done ;;
    day)   for period in "${!BY_DAY[@]}"; do
             [ "$period" = "$TODAY" ] && continue              # keep today
             SHARD_RANGES["$STEM-$period.md"]="${BY_DAY[$period]}"; rolled_any=1
           done ;;
esac

# Nothing older than the active period? nothing to do.
if [ "$rolled_any" -eq 0 ]; then
    echo "SHARD-ROLL OK: nothing to roll (active $G alone ${ACTIVE}B ≤ ceiling ${CEILING}B, no older periods)"
    exit 0
fi

# Build a set of rolled line-ranges to EXCLUDE from the new parent.
declare -A EXCL
rolled_count=0
for shard in "${!SHARD_RANGES[@]}"; do
    IFS=',' read -ra RANGES <<< "${SHARD_RANGES[$shard]}"
    for rng in "${RANGES[@]}"; do EXCL[$rng]=1; rolled_count=$((rolled_count + 1)); done
done

# Write each shard. Shards are FROZEN once written — refuse if one already exists for
# the period (F-M2: also catches a pre-placed symlink at the shard path that cat would
# otherwise read through, and the frozen-shard invariant a re-roll would violate). One
# frontmatter block per shard, written once.
SHARD_NAMES=""
for shard in "${!SHARD_RANGES[@]}"; do
    spath="$DIR/$shard"
    { [ -e "$spath" ] || [ -L "$spath" ]; } && fail "shard already exists (frozen, refuse to modify): $shard"
    [[ "$spath" =~ ^/[A-Za-z0-9/_.\ -]{1,4096}\.md$ ]] || fail "shard path fails C1/H1: $shard"
    s_tmp=$(mktemp "$DIR/.mempenny-shard-XXXXXXXX") || fail "mktemp failed"
    {
        printf -- '---\ntype: %s-shard\nperiod: %s\n---\n\n' "$STEM" "$(basename "$shard" .md | sed "s/^${STEM}-//")"
        IFS=',' read -ra RANGES <<< "${SHARD_RANGES[$shard]}"
        for rng in "${RANGES[@]}"; do s=${rng%-*}; e=${rng#*-}; sed -n "${s},${e}p" "$FILE"; printf '\n'; done
    } > "$s_tmp"
    chmod 600 "$s_tmp"; mv "$s_tmp" "$spath"
    SHARD_NAMES="$SHARD_NAMES $shard"
done
# Deterministic Shards-index order (associative-array iteration is unspecified).
# shellcheck disable=SC2086 # intentional word-splitting — shard names are space-free (H1)
SHARD_NAMES=$(printf '%s\n' $SHARD_NAMES | sort | tr '\n' ' ')

# Rebuild the parent: preamble (lines 1..PREAMBLE_END) + Shards index + every kept section.
p_tmp=$(mktemp "$DIR/.mempenny-shard-XXXXXXXX") || fail "mktemp failed"
{
    [ "$PREAMBLE_END" -ge 1 ] && sed -n "1,${PREAMBLE_END}p" "$FILE"
    printf -- '\n## Shards\n\n'
    for shard in $SHARD_NAMES; do printf -- '- [%s](%s)\n' "$shard" "$shard"; done
    printf '\n'
    while IFS='|' read -r d s e; do
        [ "${EXCL[$s-$e]:-}" = "1" ] && continue
        sed -n "${s},${e}p" "$FILE"
    done <<EOF
$READ
EOF
} > "$p_tmp"
chmod 600 "$p_tmp"

AFTER=$(wc -c < "$p_tmp" | tr -d ' ')
mv "$p_tmp" "$FILE"

# Conservation gate (PENT-7/CR-6): parent-after + all shards must account for at least
# the original bytes (they'll exceed it by the structural overhead — frontmatter, Shards
# index). A drop would make the sum fall below TOTAL. Coarse but catches lost sections.
SHARDS_BYTES=0
for shard in $SHARD_NAMES; do
    sb=$(wc -c < "$DIR/$shard" | tr -d ' ')
    SHARDS_BYTES=$((SHARDS_BYTES + sb))
done
if [ $((AFTER + SHARDS_BYTES)) -lt "$TOTAL" ]; then
    fail "conservation floor violated: parent ${AFTER} + shards ${SHARDS_BYTES} < original ${TOTAL} (a section was lost)"
fi
echo "SHARD-ROLL OK: $G; rolled $rolled_count section(s) into ${#SHARD_RANGES[@]} shard(s); parent ${TOTAL} -> ${AFTER} bytes (+${SHARDS_BYTES} in shards; conservation floor held)"
