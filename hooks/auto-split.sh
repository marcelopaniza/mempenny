#!/usr/bin/env bash
# mempenny auto-split -- content-preserving fallback for an over-ceiling topic
# file that has no other applicable automated reduction path.
#
# Covers exactly the gap /mempenny:memory-curate and /mempenny:memory-shard-roll
# leave open (docs/memory-taxonomy-design.md SS2-SS4):
#   - charter.md / pending.md -- curate-exempt by design (plain prose, no ###
#     entries; distilling requirements or in-flight work is destructive) and
#     never sharded by shard-roll (not a log-topic at all). Over-ceiling on
#     either was previously flagged for a human and left to grow forever.
#   - worklog.md / support.md / decisions.md -- shard-roll only ever closes a
#     FULLY PAST calendar year ("no mid-year shards, ever" is shard-roll's own,
#     deliberate pin). A file whose over-ceiling bulk is entirely the still-open
#     year has nowhere else to go either.
#
# Two split strategies, chosen mechanically from what the file actually
# contains -- never guessed, never an LLM judgment call:
#
#   DATE strategy (worklog/support/decisions): the file already carries
#   `## YYYY-MM` or `## YYYY-MM-DD` section headings (mempenny always writes
#   one shape or the other, newest-first, never both in the same file). Oldest
#   periods (bottom of file, by the same non-increasing-order convention
#   memory-shard-roll.md's own script already assumes and structurally
#   verifies) are peeled into one locked `<topic>-<period>.md` shard per
#   period -- exactly shard-roll's own shard shape, just not gated on calendar-
#   year closure -- stopping as soon as the kept remainder fits the ceiling.
#   The single newest period is NEVER peeled, no matter what: that floor stays
#   live, mirroring hooks/shard-roll.sh's own "today is the floor" precedent
#   (a different, not-yet-wired script -- this one doesn't call it or depend
#   on it, deliberately, see the command doc for why).
#
#   PROSE strategy (charter/pending): no heading structure exists to anchor on
#   -- expected, see docs/memory-taxonomy-design.md SS3, "plain prose, no
#   structure". Falls back to a position-based split: the file's PREFIX (head,
#   right after any YAML frontmatter) is treated as the oldest content and the
#   SUFFIX (tail) as the newest/in-flight content, under the documented
#   assumption that these files grow by appending new material at the end over
#   time. THIS ASSUMPTION IS THE OPEN DESIGN QUESTION flagged back to the
#   human -- see commands/memory-auto-split.md's "Open design question" note.
#   The cut point is the smallest peelable prefix that brings the kept suffix
#   under both ceilings, nudged forward (shrinking the shard, growing what
#   stays live -- always the ceiling-safe direction) to the nearest fence-safe
#   boundary so a fenced code block is never split across the two files.
#
# Neither strategy ever writes a `## Shards` index block -- that's the
# orchestrating command's job afterward (mirrors memory-shard-roll.md's own
# Step 7/Step 8 split: the script only ever moves bytes it already owns
# start-to-end; deciding how to describe what moved, and preserving whatever
# index lines a *prior* run already wrote, needs a Read+Edit pass this script
# deliberately does not attempt -- seeing hooks/shard-roll.sh silently drop a
# prior run's index entries by unconditionally regenerating the whole `##
# Shards` block server-side was exactly the failure mode this choice avoids).
#
# Safety properties, all reused from shard-roll/curate, none reinvented:
#   - backup already happened, by the caller, before this script ever runs.
#   - newline-normalized read (a missing trailing newline never silently drops
#     the file's last line, the same fix shard-roll/curate both needed).
#   - whole-file fence-balance precondition (refuse an odd `` ``` `` count).
#   - structural guard on date order (DATE strategy only) -- fails closed
#     rather than mis-slicing a file that doesn't hold the assumed shape.
#   - pre-flight collision check across the WHOLE batch of shards before any
#     of them is written -- a later collision can never leave earlier shards
#     half-written.
#   - conservation check modeled byte-for-byte on memory-shard-roll.md's own:
#     every non-blank, whitespace-normalized source line must be found
#     verbatim somewhere in {shard(s) + kept file} before anything commits.
#   - atomic commit: mktemp on the SAME filesystem as MEMORY_DIR + mv.
#   - shard files are frozen (`<!-- mempenny-lock -->`) the instant they're
#     written, exactly like every other mempenny shard.
#   - never peels 100% of the file -- always leaves at least the newest
#     period (DATE) or at least one line (PROSE) live.
#
# Usage: auto-split.sh <MEMORY_DIR> <topic-file-basename> <topic-type> <ceiling-bytes> <ceiling-lines>
# stdout (success, something split):  "SCRIPT_OK ..." + machine-readable fields
# stdout (success, nothing to do):    "SPLIT OK: nothing to split (...)"  (exit 0)
# stdout (failure):                   "SPLIT FAILED: <reason>"           (exit 1)

set -euo pipefail

MEMORY_DIR="${1:?usage: auto-split.sh <MEMORY_DIR> <topic-file-basename> <topic-type> <ceiling-bytes> <ceiling-lines>}"
TOPIC_BASENAME="${2:?usage: auto-split.sh <MEMORY_DIR> <topic-file-basename> <topic-type> <ceiling-bytes> <ceiling-lines>}"
TOPIC_TYPE="${3:?usage: auto-split.sh <MEMORY_DIR> <topic-file-basename> <topic-type> <ceiling-bytes> <ceiling-lines>}"
CEILING_BYTES="${4:?usage: auto-split.sh <MEMORY_DIR> <topic-file-basename> <topic-type> <ceiling-bytes> <ceiling-lines>}"
CEILING_LINES="${5:?usage: auto-split.sh <MEMORY_DIR> <topic-file-basename> <topic-type> <ceiling-bytes> <ceiling-lines>}"

fail() { echo "SPLIT FAILED: $*"; exit 1; }

# C1 / H1, mirrored verbatim from every other mempenny path/filename guard.
C1='^/[A-Za-z0-9/_.\ -]{1,4096}$'
H1='^[A-Za-z0-9][A-Za-z0-9_.\-]*\.md$'

[[ "$MEMORY_DIR" =~ $C1 ]] || fail "MEMORY_DIR fails C1"
[ -d "$MEMORY_DIR" ] || fail "MEMORY_DIR does not exist"
[ ! -L "$MEMORY_DIR" ] || fail "MEMORY_DIR is a symlink (F-M2)"
[[ "$TOPIC_BASENAME" =~ $H1 ]] || fail "topic filename fails H1: $TOPIC_BASENAME"

# Reserved-topic check: auto-split only ever targets the 5 files that have no
# OTHER applicable path (docs/memory-taxonomy-design.md SS2-SS4). traps.md /
# rules.md / reference.md (and their sub-topic splits) go through curate, not
# here -- curate's per-entry judgment is strictly better when it applies.
case "$TOPIC_BASENAME" in
  charter.md|pending.md|worklog.md|support.md|decisions.md) : ;;
  *) fail "'$TOPIC_BASENAME' is not one of the 5 auto-split-eligible files (charter/pending/worklog/support/decisions) -- traps/rules/reference go through /mempenny:memory-curate instead" ;;
esac

[[ "$CEILING_BYTES" =~ ^[0-9]+$ ]] || fail "ceiling-bytes must be a positive integer"
[[ "$CEILING_LINES" =~ ^[0-9]+$ ]] || fail "ceiling-lines must be a positive integer"
[ "$CEILING_BYTES" -gt 0 ] || fail "ceiling-bytes must be > 0"
[ "$CEILING_LINES" -gt 0 ] || fail "ceiling-lines must be > 0"

TOPIC_FILE="$MEMORY_DIR/$TOPIC_BASENAME"
[ -f "$TOPIC_FILE" ] || fail "topic file does not exist: $TOPIC_FILE"
[ ! -L "$TOPIC_FILE" ] || fail "topic file is a symlink (F-M2)"

# Lock re-check (TOCTOU close) -- the caller already checked before backup;
# re-checking here, immediately before any write, is the same discipline
# every other mempenny apply step uses.
for marker in ".mempenny-lock" ".mempenny-fixture"; do
  if [ -L "$MEMORY_DIR/$marker" ] || [ -e "$MEMORY_DIR/$marker" ]; then
    fail "memory dir is lock-marked ($marker) -- refusing to touch it"
  fi
done
if grep -qE '<!--[[:space:]]*mempenny-lock[[:space:]]*-->' "$TOPIC_FILE" 2>/dev/null; then
  fail "'$TOPIC_BASENAME' is mempenny-locked -- refusing to touch it"
fi

STEM=$(basename "$TOPIC_FILE" .md)

# Newline-normalize before any line-counting or line-range extraction -- wc -l
# and `while read` both silently drop a file's last line when it lacks a
# trailing newline (the exact bug memory-taxonomy-design.md's Implementation
# notes records shard-roll/curate needing this same fix for).
if [ -s "$TOPIC_FILE" ] && [ -n "$(tail -c1 "$TOPIC_FILE")" ]; then
  printf '\n' >> "$TOPIC_FILE"
fi

BEFORE_BYTES=$(wc -c < "$TOPIC_FILE" | tr -d ' ')
BEFORE_LINES=$(awk 'END{print NR}' "$TOPIC_FILE")

# Idempotency / safety floor: never split a file that doesn't need it. A
# second run right after a successful split is expected to land here and
# report cleanly rather than doing anything.
if [ "$BEFORE_BYTES" -le "$CEILING_BYTES" ] && [ "$BEFORE_LINES" -le "$CEILING_LINES" ]; then
  echo "SPLIT OK: nothing to split ($TOPIC_BASENAME is $BEFORE_BYTES B / $BEFORE_LINES lines, already at or under ceiling $CEILING_BYTES B / $CEILING_LINES lines)"
  exit 0
fi

FENCE_COUNT=$(grep -c '^```' "$TOPIC_FILE" || true)
if [ $((FENCE_COUNT % 2)) -ne 0 ]; then
  fail "$TOPIC_BASENAME has an odd number of \`\`\` fence lines ($FENCE_COUNT) -- refusing to extract from a file with unbalanced fences"
fi

# --- detect which strategy applies (fence-aware, mechanical, no judgment) ---
#
# Trailing-whitespace tolerance ([[:space:]]*$ rather than a bare $) matches
# hooks/shard-roll.sh's day-heading pattern rather than memory-shard-roll.md's
# stricter month pattern -- deliberately the more permissive of the two
# existing precedents, since being slightly more permissive about a heading
# line only ever means recognizing MORE real headings, never mis-splitting.
DAY_LINES=$(awk '
  /^```/ { infence = !infence; next }
  !infence && /^## [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9][[:space:]]*$/ { print NR ":" $0 }
' "$TOPIC_FILE")

MONTH_LINES=""
if [ -z "$DAY_LINES" ]; then
  MONTH_LINES=$(awk '
    /^```/ { infence = !infence; next }
    !infence && /^## [0-9][0-9][0-9][0-9]-[0-9][0-9][[:space:]]*$/ { print NR ":" $0 }
  ' "$TOPIC_FILE")
fi

if [ -n "$DAY_LINES" ]; then
  GRANULARITY="day"; HEADING_LINES="$DAY_LINES"
elif [ -n "$MONTH_LINES" ]; then
  GRANULARITY="month"; HEADING_LINES="$MONTH_LINES"
else
  GRANULARITY="prose"; HEADING_LINES=""
fi

SHARD_FILES=()

if [ "$GRANULARITY" != "prose" ]; then
  # ============================== DATE strategy ==============================
  ENTRY_LINES=(); ENTRY_PERIODS=()
  while IFS=: read -r ln heading; do
    period=$(printf '%s' "$heading" | sed -E 's/^## ([0-9-]+).*/\1/')
    ENTRY_LINES+=("$ln"); ENTRY_PERIODS+=("$period")
  done < <(printf '%s\n' "$HEADING_LINES")

  # Structural guard, exact analog of memory-shard-roll.md's PREV_YEAR check:
  # periods must be non-increasing top-to-bottom (newest first). ISO-8601,
  # zero-padded YYYY-MM / YYYY-MM-DD strings sort lexically == chronologically,
  # so a plain string compare is exact, not an approximation.
  PREV=""
  for p in "${ENTRY_PERIODS[@]}"; do
    if [ -n "$PREV" ] && [[ "$p" > "$PREV" ]]; then
      fail "structural check failed -- period $p appears after period $PREV in file order (expected non-increasing, newest-first). Do not guess; a human should look at this file."
    fi
    PREV="$p"
  done

  DISTINCT_PERIODS=()
  declare -A PERIOD_FIRST_LINE
  for i in "${!ENTRY_PERIODS[@]}"; do
    p="${ENTRY_PERIODS[$i]}"
    if [ -z "${PERIOD_FIRST_LINE[$p]:-}" ]; then
      PERIOD_FIRST_LINE[$p]="${ENTRY_LINES[$i]}"
      DISTINCT_PERIODS+=("$p")
    fi
  done
  TOTAL_LINES=$(awk 'END{print NR}' "$TOPIC_FILE")

  declare -A PERIOD_START PERIOD_END
  for i in "${!DISTINCT_PERIODS[@]}"; do
    p="${DISTINCT_PERIODS[$i]}"
    PERIOD_START[$p]="${PERIOD_FIRST_LINE[$p]}"
    next_idx=$((i + 1))
    if [ "$next_idx" -lt "${#DISTINCT_PERIODS[@]}" ]; then
      next_p="${DISTINCT_PERIODS[$next_idx]}"
      PERIOD_END[$p]=$((${PERIOD_FIRST_LINE[$next_p]} - 1))
    else
      PERIOD_END[$p]="$TOTAL_LINES"
    fi
  done

  FIRST_HEADING_LINE="${ENTRY_LINES[0]}"
  PREAMBLE_END=$((FIRST_HEADING_LINE - 1))
  PREAMBLE_BYTES=0
  if [ "$PREAMBLE_END" -ge 1 ]; then PREAMBLE_BYTES=$(sed -n "1,${PREAMBLE_END}p" "$TOPIC_FILE" | wc -c | tr -d ' '); fi

  N_PERIODS="${#DISTINCT_PERIODS[@]}"
  if [ "$N_PERIODS" -eq 1 ]; then
    echo "SPLIT OK: nothing to split ($TOPIC_BASENAME has only one $GRANULARITY period [${DISTINCT_PERIODS[0]}] -- no older content exists to peel off; auto-split never removes the current period)"
    exit 0
  fi

  range_bytes() { sed -n "${1},${2}p" "$TOPIC_FILE" | wc -c | tr -d ' '; }
  declare -A PERIOD_BYTES PERIOD_LINECOUNT
  for p in "${DISTINCT_PERIODS[@]}"; do
    s="${PERIOD_START[$p]}"; e="${PERIOD_END[$p]}"
    PERIOD_BYTES[$p]=$(range_bytes "$s" "$e")
    PERIOD_LINECOUNT[$p]=$((e - s + 1))
  done

  # Overhead the KEPT file always carries once the orchestrating command adds
  # its `## Shards` block afterward (this script itself writes none) -- a
  # small fixed allowance, same "+200" precedent as hooks/shard-roll.sh.
  OVERHEAD_BYTES=$((PREAMBLE_BYTES + 200))
  OVERHEAD_LINES=$((PREAMBLE_END + 10))

  # Walk newest -> oldest accumulating what would stay live; KEEP_COUNT is the
  # largest number of newest-first periods whose cumulative size still fits.
  # The newest period (index 0) is always kept, floor enforced below, no
  # matter how large it is alone -- unlike shard-roll's own "wait for the
  # period to close" luxury, auto-split is the last resort for these 5 files;
  # doing nothing would mean NO tool ever reduces them.
  KEEP_COUNT=$N_PERIODS
  cum_bytes=$OVERHEAD_BYTES
  cum_lines=$OVERHEAD_LINES
  for ((i = 0; i < N_PERIODS; i++)); do
    p="${DISTINCT_PERIODS[$i]}"
    cum_bytes=$((cum_bytes + PERIOD_BYTES[$p]))
    cum_lines=$((cum_lines + PERIOD_LINECOUNT[$p]))
    if [ "$cum_bytes" -gt "$CEILING_BYTES" ] || [ "$cum_lines" -gt "$CEILING_LINES" ]; then
      KEEP_COUNT=$i
      break
    fi
  done
  [ "$KEEP_COUNT" -lt 1 ] && KEEP_COUNT=1

  if [ "$KEEP_COUNT" -ge "$N_PERIODS" ]; then
    echo "SPLIT OK: nothing to split ($TOPIC_BASENAME fits under ceiling once measured period-by-period)"
    exit 0
  fi

  TO_SHARD_PERIODS=("${DISTINCT_PERIODS[@]:$KEEP_COUNT}")
  last_kept_period="${DISTINCT_PERIODS[$((KEEP_COUNT - 1))]}"
  KEPT_END="${PERIOD_END[$last_kept_period]}"

  # Pre-flight collision check across the WHOLE batch before writing anything
  # -- a collision on a later period can never leave earlier ones half-done.
  for p in "${TO_SHARD_PERIODS[@]}"; do
    shard="$MEMORY_DIR/$STEM-$p.md"
    if [ -e "$shard" ] || [ -L "$shard" ]; then
      fail "shard collision: $(basename "$shard") already exists -- refusing the whole batch (nothing written)"
    fi
    [[ "$shard" =~ $C1 ]] || fail "shard path fails C1: $shard"
  done

  for p in "${TO_SHARD_PERIODS[@]}"; do
    shard="$MEMORY_DIR/$STEM-$p.md"
    s_tmp=$(mktemp "$MEMORY_DIR/.mempenny-autosplit-XXXXXXXX") || fail "mktemp failed"
    { printf -- '---\ntype: %s\n---\n<!-- mempenny-lock -->\n' "$TOPIC_TYPE"
      sed -n "${PERIOD_START[$p]},${PERIOD_END[$p]}p" "$TOPIC_FILE"
    } > "$s_tmp"
    chmod 600 "$s_tmp"
    mv "$s_tmp" "$shard"
    SHARD_FILES+=("$(basename "$shard")")
  done

  KEPT_TMP=$(mktemp "$MEMORY_DIR/.mempenny-autosplit-XXXXXXXX") || fail "mktemp failed"
  sed -n "1,${KEPT_END}p" "$TOPIC_FILE" > "$KEPT_TMP"

else
  # ============================== PROSE strategy ==============================
  # No date-heading structure anywhere in the file -- expected for
  # charter.md/pending.md. See the file header comment for the documented
  # (and explicitly flagged) "content is appended at the end over time"
  # assumption this direction relies on.
  FRONTMATTER_END=0
  if [ "$(sed -n '1p' "$TOPIC_FILE")" = "---" ]; then
    fm_end=$(awk 'NR>1 && $0=="---" { print NR; exit }' "$TOPIC_FILE")
    [ -n "${fm_end:-}" ] && FRONTMATTER_END="$fm_end"
  fi

  TOTAL_BYTES_FILE=$(wc -c < "$TOPIC_FILE" | tr -d ' ')
  TOTAL_LINES_FILE=$(awk 'END{print NR}' "$TOPIC_FILE")

  FRONTMATTER_BYTES=0
  if [ "$FRONTMATTER_END" -ge 1 ]; then FRONTMATTER_BYTES=$(sed -n "1,${FRONTMATTER_END}p" "$TOPIC_FILE" | wc -c | tr -d ' '); fi

  if [ "$FRONTMATTER_END" -ge "$((TOTAL_LINES_FILE - 1))" ]; then
    fail "$TOPIC_BASENAME has no peelable content outside its frontmatter -- a human should look at this file"
  fi

  # Smallest CUT (>= FRONTMATTER_END) such that the suffix (CUT+1..EOF) fits
  # both ceilings. suffix_bytes and suffix_lines are both non-increasing as
  # CUT grows, so a single forward pass finds the minimum directly -- no
  # search needed. Peeled range is (FRONTMATTER_END, CUT]; kept range is
  # 1..FRONTMATTER_END plus (CUT, TOTAL_LINES_FILE].
  CUT="$FRONTMATTER_END"
  prefix_bytes="$FRONTMATTER_BYTES"
  while IFS= read -r -d '' llen; do
    CUT=$((CUT + 1))
    prefix_bytes=$((prefix_bytes + llen))
    suffix_bytes=$((TOTAL_BYTES_FILE - prefix_bytes))
    suffix_lines=$((TOTAL_LINES_FILE - CUT))
    if [ "$suffix_bytes" -le "$CEILING_BYTES" ] && [ "$suffix_lines" -le "$CEILING_LINES" ]; then
      break
    fi
  done < <(tail -n "+$((FRONTMATTER_END + 1))" "$TOPIC_FILE" | awk '{ printf "%d\0", length($0) + 1 }')

  # Floor: always leave at least the file's last line live, no matter how big
  # it alone is -- mirrors the DATE strategy's "newest period always survives".
  if [ "$CUT" -ge "$TOTAL_LINES_FILE" ]; then
    CUT=$((TOTAL_LINES_FILE - 1))
  fi

  # Fence-safety nudge: walk CUT FORWARD (shrinking the shard, growing what
  # stays live -- the only ceiling-safe direction) to the nearest boundary
  # where the peeled prefix (1..CUT) has an EVEN `` ``` `` count. The whole
  # file is already confirmed even, so CUT=TOTAL_LINES_FILE is trivially safe
  # -- the loop is bounded by the "leave at least one line live" floor below,
  # not by an unbounded search.
  is_even_fence_prefix() {
    local n="$1" c
    c=$(sed -n "1,${n}p" "$TOPIC_FILE" | grep -c '^```' || true)
    [ $((c % 2)) -eq 0 ]
  }
  while [ "$CUT" -lt "$((TOTAL_LINES_FILE - 1))" ] && ! is_even_fence_prefix "$CUT"; do
    CUT=$((CUT + 1))
  done
  is_even_fence_prefix "$CUT" || fail "no fence-safe split boundary found without shredding the entire file -- a human should look at $TOPIC_BASENAME's fenced code blocks"

  if [ "$CUT" -le "$FRONTMATTER_END" ]; then
    echo "SPLIT OK: nothing to split ($TOPIC_BASENAME has no peelable content once frontmatter and fence-safety are accounted for)"
    exit 0
  fi

  TODAY=$(date -u +%Y-%m-%d)
  shard="$MEMORY_DIR/$STEM-archive-$TODAY.md"
  if [ -e "$shard" ] || [ -L "$shard" ]; then
    fail "shard collision: $(basename "$shard") already exists -- a split already ran today for $TOPIC_BASENAME. If the file is over ceiling again, this is a second genuine episode on the same day; resolve manually (rename the existing archive shard, or wait for tomorrow's date)."
  fi
  [[ "$shard" =~ $C1 ]] || fail "shard path fails C1: $shard"

  s_tmp=$(mktemp "$MEMORY_DIR/.mempenny-autosplit-XXXXXXXX") || fail "mktemp failed"
  { printf -- '---\ntype: %s\n---\n<!-- mempenny-lock -->\n' "$TOPIC_TYPE"
    if [ "$FRONTMATTER_END" -ge 1 ]; then
      sed -n "$((FRONTMATTER_END + 1)),${CUT}p" "$TOPIC_FILE"
    else
      sed -n "1,${CUT}p" "$TOPIC_FILE"
    fi
  } > "$s_tmp"
  chmod 600 "$s_tmp"
  mv "$s_tmp" "$shard"
  SHARD_FILES+=("$(basename "$shard")")

  KEPT_TMP=$(mktemp "$MEMORY_DIR/.mempenny-autosplit-XXXXXXXX") || fail "mktemp failed"
  {
    if [ "$FRONTMATTER_END" -ge 1 ]; then sed -n "1,${FRONTMATTER_END}p" "$TOPIC_FILE"; fi
    sed -n "$((CUT + 1)),${TOTAL_LINES_FILE}p" "$TOPIC_FILE"
  } > "$KEPT_TMP"
fi

# ============================== shared: verify + commit ==============================

for f in "${SHARD_FILES[@]}"; do
  fc=$(grep -c '^```' "$MEMORY_DIR/$f" || true)
  if [ $((fc % 2)) -ne 0 ]; then
    echo "SPLIT FAILED: extraction produced an unbalanced fence count in $f -- aborting before touching $TOPIC_BASENAME"
    for sf in "${SHARD_FILES[@]}"; do rm -f "$MEMORY_DIR/$sf"; done
    rm -f "$KEPT_TMP"
    exit 1
  fi
done
kfc=$(grep -c '^```' "$KEPT_TMP" || true)
if [ $((kfc % 2)) -ne 0 ]; then
  echo "SPLIT FAILED: extraction produced an unbalanced fence count in the kept remainder -- aborting before touching $TOPIC_BASENAME"
  for sf in "${SHARD_FILES[@]}"; do rm -f "$MEMORY_DIR/$sf"; done
  rm -f "$KEPT_TMP"
  exit 1
fi

# Conservation check -- modeled byte-for-byte on memory-shard-roll.md's own:
# every non-blank, whitespace-normalized line of the ORIGINAL file must be
# found verbatim somewhere in {every shard + the kept remainder}.
HAYSTACK=$(mktemp)
{ for f in "${SHARD_FILES[@]}"; do sed 's/^[[:space:]]*//; s/[[:space:]]*$//' "$MEMORY_DIR/$f"; done
  sed 's/^[[:space:]]*//; s/[[:space:]]*$//' "$KEPT_TMP"
} > "$HAYSTACK"
MISSING=0
while IFS= read -r line || [ -n "$line" ]; do
  norm=$(printf '%s' "$line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
  [ -z "$norm" ] && continue
  if ! grep -qFx -- "$norm" "$HAYSTACK"; then
    MISSING=$((MISSING + 1)); echo "MISSING: $norm"
  fi
done < <(sed 's/^[[:space:]]*//; s/[[:space:]]*$//' "$TOPIC_FILE")
echo "TOTAL_MISSING=$MISSING"

if [ "$MISSING" -gt 0 ]; then
  for f in "${SHARD_FILES[@]}"; do rm -f "$MEMORY_DIR/$f"; done
  rm -f "$KEPT_TMP" "$HAYSTACK"
  echo "SPLIT FAILED: conservation check found $MISSING unaccounted lines"
  exit 1
fi

mv "$KEPT_TMP" "$TOPIC_FILE"
rm -f "$HAYSTACK"

AFTER_BYTES=$(wc -c < "$TOPIC_FILE")
AFTER_LINES=$(awk 'END{print NR}' "$TOPIC_FILE")
SHARD_SIZES=()
for f in "${SHARD_FILES[@]}"; do
  SHARD_SIZES+=("$f ($(wc -c < "$MEMORY_DIR/$f") B)")
done
SHARD_LIST=$(IFS=,; echo "${SHARD_SIZES[*]}")

echo "SCRIPT_OK"
echo "GRANULARITY=$GRANULARITY"
echo "SHARD_FILES_WRITTEN: $SHARD_LIST"
echo "BEFORE_BYTES=$BEFORE_BYTES"
echo "AFTER_BYTES=$AFTER_BYTES"
echo "AFTER_LINES=$AFTER_LINES"
