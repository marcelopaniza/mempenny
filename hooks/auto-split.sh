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
# UNIFYING PRINCIPLE: over ceiling -> the main file becomes an INDEX, and the
# items it used to hold become PAGES the index points at. Three strategies
# below are three expressions of the same rule, chosen mechanically from what
# the file actually contains -- never guessed, never an LLM judgment call --
# plus one last-resort fallback for content with no structure to index at all:
#
#   1. DATE (worklog/support/decisions): the file already carries `## YYYY-MM`
#      or `## YYYY-MM-DD` section headings (mempenny always writes one shape
#      or the other, newest-first, never both in the same file). The
#      CHRONOLOGICAL expression of the index/pages rule -- the parent's own
#      `## Shards` index block (added by the orchestrating command, not this
#      script) IS the index; the locked `<topic>-<period>.md` shard files ARE
#      the pages. Oldest periods (bottom of file, non-increasing order,
#      structurally verified) are peeled into one page per period -- exactly
#      shard-roll's own shard shape, just not gated on calendar-year closure
#      -- stopping as soon as the kept remainder fits the ceiling. The single
#      newest period is NEVER peeled, no matter how large it is alone -- that
#      floor stays live, mirroring hooks/shard-roll.sh's own "today is the
#      floor" precedent (a different, not-yet-wired script -- this one
#      doesn't call it or depend on it, deliberately, see the command doc).
#
#   2. SUBJECT-INDEX (charter/pending, when `## `-structured): the SUBJECT
#      expression of the same rule, and the primary strategy for a real
#      pending.md (verified: frontmatter, a preamble, dozens of top-level
#      `## ` subject blocks -- each an independent item, sometimes with
#      nested `### ` detail that stays inside its parent -- newest at the
#      TOP). Every top-level `## ` block becomes its own detail PAGE; the
#      live file becomes the INDEX outright: frontmatter + preamble + one
#      bullet per subject, original (file) order, each pointing at its page.
#      Unlike DATE and PROSE-PEEL below, this never "peels the oldest and
#      keeps some live" -- ALL currently-unindexed blocks become pages in one
#      pass, because the index itself (all bullets, present) is what stays
#      live and small. Detail pages are deliberately left UNLOCKED (see the
#      command doc for why -- it's a feature, not an oversight).
#
#   3. PROSE-PEEL (charter/pending, only when NEITHER of the above applies --
#      no date headings, fewer than 2 `## ` blocks): the last-resort fallback
#      for genuinely structureless prose that still carries datestamps. Falls
#      back to a position-based split, direction DERIVED from the file's own
#      datestamps, never assumed: scans the body (outside frontmatter) for
#      the first and last `YYYY-MM-DD` (or, failing that, `YYYY-MM`) it can
#      find and compares them.
#        - newest-first (top date > bottom date): oldest = SUFFIX (bottom) --
#          shard the suffix, keep the PREFIX (top) live.
#        - newest-last (top date < bottom date, content appended at the
#          end): oldest = PREFIX (top) -- shard the prefix, keep the SUFFIX
#          (bottom) live.
#      No datestamp anywhere, or only one distinct date (no direction to
#      derive), falls through to:
#
#   4. REFUSE CLOSED: a headingless, dateless file (a bare charter.md is the
#      common real shape -- goals/requirements prose rarely carries dates)
#      has nothing this script can safely index, peel, or order. Reported for
#      manual trimming instead of guessing.
#
# For strategies 2 and 3, either direction/case, a fence-safety nudge always
# moves the cut toward whichever side is becoming a PAGE (never the side
# staying live as the INDEX/kept content) -- the ceiling-safe direction,
# whichever end that happens to be -- so a fenced code block is never split
# across two files.
#
# Neither strategy writes a `## Shards` index block for DATE, and SUBJECT-
# INDEX's own index IS the whole live file it writes directly (no separate
# index-block step needed) -- see the command doc's Step 6 for exactly which
# half of index-maintenance is this script's job vs. the orchestrating
# command's.
#
# Safety properties, all reused from shard-roll/curate, none reinvented:
#   - backup already happened, by the caller, before this script ever runs.
#   - newline-normalized read (a missing trailing newline never silently drops
#     the file's last line, the same fix shard-roll/curate both needed).
#   - whole-file fence-balance precondition (refuse an odd `` ``` `` count).
#   - structural guard on date order (DATE strategy only) -- fails closed
#     rather than mis-slicing a file that doesn't hold the assumed shape.
#   - pre-flight collision check across the WHOLE batch of pages before any
#     of them is written -- a later collision can never leave earlier pages
#     half-written.
#   - conservation check modeled byte-for-byte on memory-shard-roll.md's own:
#     every non-blank, whitespace-normalized source line must be found
#     verbatim somewhere in {page(s) + kept/index file} before anything
#     commits. New index bullets are additions, not replacements of source
#     lines, so the missing-only check permits them without weakening it.
#   - atomic commit: mktemp on the SAME filesystem as MEMORY_DIR + mv.
#   - DATE and PROSE-PEEL pages are frozen (`<!-- mempenny-lock -->`) the
#     instant they're written, like every other mempenny shard. SUBJECT-INDEX
#     pages are deliberately NOT locked (see the command doc).
#   - never discards content -- DATE/PROSE-PEEL always leave at least the
#     newest period/one line live; SUBJECT-INDEX always represents every
#     block via an index bullet, none silently dropped.
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
# report cleanly rather than doing anything -- this is also what makes a
# fully-collapsed SUBJECT-INDEX file (frontmatter + preamble + bullets, no
# raw `## ` blocks left) a trivial no-op with zero special-case code: an
# all-bullets index is small by construction and simply never gets past this
# check on a re-run.
if [ "$BEFORE_BYTES" -le "$CEILING_BYTES" ] && [ "$BEFORE_LINES" -le "$CEILING_LINES" ]; then
  echo "SPLIT OK: nothing to split ($TOPIC_BASENAME is $BEFORE_BYTES B / $BEFORE_LINES lines, already at or under ceiling $CEILING_BYTES B / $CEILING_LINES lines)"
  exit 0
fi

FENCE_COUNT=$(grep -c '^```' "$TOPIC_FILE" || true)
if [ $((FENCE_COUNT % 2)) -ne 0 ]; then
  fail "$TOPIC_BASENAME has an odd number of \`\`\` fence lines ($FENCE_COUNT) -- refusing to extract from a file with unbalanced fences"
fi

# Frontmatter span -- shared by every strategy below (DATE never uses it
# directly since its own preamble math is self-contained, but SUBJECT-INDEX
# and PROSE-PEEL both need it, and computing it once here avoids the two
# strategies' copies drifting apart).
FRONTMATTER_END=0
if [ "$(sed -n '1p' "$TOPIC_FILE")" = "---" ]; then
  fm_end=$(awk 'NR>1 && $0=="---" { print NR; exit }' "$TOPIC_FILE")
  [ -n "${fm_end:-}" ] && FRONTMATTER_END="$fm_end"
fi
FRONTMATTER_BYTES=0
if [ "$FRONTMATTER_END" -ge 1 ]; then FRONTMATTER_BYTES=$(sed -n "1,${FRONTMATTER_END}p" "$TOPIC_FILE" | wc -c | tr -d ' '); fi
TOTAL_LINES_FILE=$(awk 'END{print NR}' "$TOPIC_FILE")
TOTAL_BYTES_FILE=$(wc -c < "$TOPIC_FILE" | tr -d ' ')

is_even_fence_prefix() {
  local n="$1" c
  c=$(sed -n "1,${n}p" "$TOPIC_FILE" | grep -c '^```' || true)
  [ $((c % 2)) -eq 0 ]
}

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

GRANULARITY=""
if [ -n "$DAY_LINES" ]; then
  GRANULARITY="day"; HEADING_LINES="$DAY_LINES"
elif [ -n "$MONTH_LINES" ]; then
  GRANULARITY="month"; HEADING_LINES="$MONTH_LINES"
fi

# SUBJECT-INDEX eligibility is only even checked if DATE didn't already claim
# the file. Generic `## ` heading (exactly two hashes -- `^## ` never matches
# a `### ` line, since its third character is `#`, not the required space, so
# nested `###` detail is structurally excluded with no extra logic needed).
SUBJECT_LINES=""
if [ -z "$GRANULARITY" ]; then
  SUBJECT_LINES=$(awk '
    /^```/ { infence = !infence; next }
    !infence && /^## [^[:space:]]/ { print NR ":" $0 }
  ' "$TOPIC_FILE")
fi

if [ -z "$GRANULARITY" ] && [ -n "$SUBJECT_LINES" ]; then
  SUBJECT_COUNT=$(printf '%s\n' "$SUBJECT_LINES" | grep -c . || true)
  if [ "$SUBJECT_COUNT" -ge 2 ]; then
    GRANULARITY="subject-index"
  elif [ "$SUBJECT_COUNT" -eq 1 ]; then
    # Exactly one raw block: only commit to SUBJECT-INDEX if there's already
    # an established index tail after it (this run is continuing a prior
    # split, e.g. exactly one new subject was prepended since) -- otherwise a
    # single incidental `## ` heading in otherwise-plain prose isn't strong
    # enough evidence of real subject structure, and the file falls through
    # to PROSE-PEEL/refuse like it would have with zero headings.
    one_line=$(printf '%s\n' "$SUBJECT_LINES" | head -1)
    one_ln="${one_line%%:*}"
    tail_probe=$(sed -n "$((one_ln + 1)),\$p" "$TOPIC_FILE" | { grep -qE "^- \[.*\]\(${STEM}-[0-9]+.*\.md\)\$" && echo yes || true; })
    [ "$tail_probe" = "yes" ] && GRANULARITY="subject-index"
  fi
fi

if [ -z "$GRANULARITY" ]; then
  GRANULARITY="prose-peel"
fi

SHARD_FILES=()

if [ "$GRANULARITY" = "day" ] || [ "$GRANULARITY" = "month" ]; then
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

  declare -A PERIOD_START PERIOD_END
  for i in "${!DISTINCT_PERIODS[@]}"; do
    p="${DISTINCT_PERIODS[$i]}"
    PERIOD_START[$p]="${PERIOD_FIRST_LINE[$p]}"
    next_idx=$((i + 1))
    if [ "$next_idx" -lt "${#DISTINCT_PERIODS[@]}" ]; then
      next_p="${DISTINCT_PERIODS[$next_idx]}"
      PERIOD_END[$p]=$((${PERIOD_FIRST_LINE[$next_p]} - 1))
    else
      PERIOD_END[$p]="$TOTAL_LINES_FILE"
    fi
  done

  DATE_PREAMBLE_END=$((ENTRY_LINES[0] - 1))
  DATE_PREAMBLE_BYTES=0
  if [ "$DATE_PREAMBLE_END" -ge 1 ]; then DATE_PREAMBLE_BYTES=$(sed -n "1,${DATE_PREAMBLE_END}p" "$TOPIC_FILE" | wc -c | tr -d ' '); fi

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
  OVERHEAD_BYTES=$((DATE_PREAMBLE_BYTES + 200))
  OVERHEAD_LINES=$((DATE_PREAMBLE_END + 10))

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

elif [ "$GRANULARITY" = "subject-index" ]; then
  # ============================== SUBJECT-INDEX strategy ==============================
  # See file header for the unifying principle. Unit = one top-level `## `
  # block: heading line through the line before the next fence-aware `## `
  # (or EOF, or the start of an already-existing index tail -- see below).
  # `### ` stays inside its parent by construction (see the detection regex
  # above). Every block becomes its own detail PAGE; the live file becomes
  # the INDEX: frontmatter + preamble + one bullet per subject, original
  # (file) order, each pointing at its page.
  ENTRY_LINES=(); ENTRY_HEADING_RAW=()
  while IFS=: read -r ln heading; do
    ENTRY_LINES+=("$ln"); ENTRY_HEADING_RAW+=("$heading")
  done < <(printf '%s\n' "$SUBJECT_LINES")

  N_ENTRIES="${#ENTRY_LINES[@]}"
  SUBJ_PREAMBLE_END=$((ENTRY_LINES[0] - 1))

  declare -a BLOCK_END
  for ((i = 0; i < N_ENTRIES; i++)); do
    next_idx=$((i + 1))
    if [ "$next_idx" -lt "$N_ENTRIES" ]; then
      BLOCK_END[i]=$((ENTRY_LINES[next_idx] - 1))
    else
      BLOCK_END[i]="$TOTAL_LINES_FILE"
    fi
  done

  # Existing-index detection: scan the LAST block's own (naive) range for the
  # first line matching THIS script's own index-bullet shape -- everything
  # from there to EOF is a PRIOR run's already-collapsed index, preserved
  # verbatim, never re-parsed as part of the last new block's body. A block
  # that once had a `## ` heading loses it entirely once collapsed to a bare
  # bullet, so it can never be mistaken for a genuine still-to-split block on
  # a later run -- this scan only ever has real work to do on the trailing
  # region right after the newest of THIS run's raw blocks.
  EXISTING_INDEX_START=0
  last_idx=$((N_ENTRIES - 1))
  last_block_body_start=$((ENTRY_LINES[last_idx] + 1))
  last_block_naive_end="${BLOCK_END[$last_idx]}"
  if [ "$last_block_body_start" -le "$last_block_naive_end" ]; then
    found_rel=$(sed -n "${last_block_body_start},${last_block_naive_end}p" "$TOPIC_FILE" \
      | { grep -nE "^- \[.*\]\(${STEM}-[0-9]+.*\.md\)\$" || true; } | head -1 | cut -d: -f1)
    if [ -n "${found_rel:-}" ]; then
      EXISTING_INDEX_START=$((last_block_body_start + found_rel - 1))
      BLOCK_END[last_idx]=$((EXISTING_INDEX_START - 1))
    fi
  fi

  # Existing max NN already on disk for this topic -- new pages continue
  # numbering from there rather than restarting at 01, so a later run that
  # prepends fresh blocks can never collide with pages an earlier run already
  # wrote (see the command doc's SUBJECT-INDEX section for the full
  # rationale). `10#` forces base-10 parsing so a zero-padded value like "08"
  # is never misread as an invalid octal literal.
  EXISTING_MAX_NN=0
  for f in "$MEMORY_DIR/$STEM"-[0-9][0-9]*.md; do
    [ -e "$f" ] || continue
    nn_part=$(basename "$f" .md | sed -E "s/^${STEM}-([0-9]+).*/\1/")
    [[ "$nn_part" =~ ^[0-9]+$ ]] || continue
    nn_val=$((10#$nn_part))
    [ "$nn_val" -gt "$EXISTING_MAX_NN" ] && EXISTING_MAX_NN="$nn_val"
  done

  # ASCII-only slug: strips a leading/embedded YYYY-MM-DD date token first
  # (before general stripping, so its hyphens aren't mistaken for word
  # separators), then keeps only letters/digits/spaces -- which safely and
  # correctly removes emoji too, since every byte of a multi-byte UTF-8
  # sequence falls outside A-Za-z0-9 (UTF-8 is designed so ASCII byte values
  # never appear inside a multi-byte sequence, so this never mangles a
  # partial character, it just deletes the whole thing cleanly).
  slugify() {
    local heading="$1" slug
    slug=$(printf '%s' "$heading" | sed -E 's/[0-9]{4}-[0-9]{2}-[0-9]{2}//g')
    slug=$(printf '%s' "$slug" | tr -cd 'A-Za-z0-9 ')
    slug=$(printf '%s' "$slug" | tr -s '[:space:]' ' ' | sed -E 's/^ +| +$//g' | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
    slug=$(printf '%s' "$slug" | cut -c1-40 | sed -E 's/-+$//; s/^-+//')
    printf '%s' "$slug"
  }
  yaml_dquote() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
  md_link_text() { printf '%s' "$1" | sed 's/\[/\\[/g; s/\]/\\]/g'; }

  ENTRY_FILE=(); ENTRY_HEADING_TEXT=()
  nn_counter="$EXISTING_MAX_NN"
  for ((i = 0; i < N_ENTRIES; i++)); do
    heading_text=$(printf '%s' "${ENTRY_HEADING_RAW[$i]}" | sed -E 's/^## //')
    nn_counter=$((nn_counter + 1))
    nn=$(printf '%02d' "$nn_counter")
    slug=$(slugify "$heading_text")
    if [ -n "$slug" ]; then candidate="$STEM-$nn-$slug"; else candidate="$STEM-$nn"; fi
    # Deterministic collision fallback (append -2, -3, ...). NN is unique per
    # entry by construction (nn_counter strictly increases every iteration),
    # so this can only ever fire against a pre-existing file from some OTHER
    # source (hand-created, or a differently-shaped prior run) -- not against
    # anything this same run itself is about to write.
    suffix=1
    final="$candidate"
    while [ -e "$MEMORY_DIR/$final.md" ] || [ -L "$MEMORY_DIR/$final.md" ]; do
      suffix=$((suffix + 1))
      final="$candidate-$suffix"
    done
    [[ "$final.md" =~ $H1 ]] || fail "generated detail filename fails H1: $final.md"
    ENTRY_FILE+=("$final.md"); ENTRY_HEADING_TEXT+=("$heading_text")
  done

  for ((i = 0; i < N_ENTRIES; i++)); do
    s_tmp=$(mktemp "$MEMORY_DIR/.mempenny-autosplit-XXXXXXXX") || fail "mktemp failed"
    {
      printf -- '---\nname: %s\ndescription: "%s"\nmetadata:\n  type: %s\n---\n' \
        "$(basename "${ENTRY_FILE[$i]}" .md)" "$(yaml_dquote "${ENTRY_HEADING_TEXT[$i]}")" "$TOPIC_TYPE"
      sed -n "${ENTRY_LINES[$i]},${BLOCK_END[$i]}p" "$TOPIC_FILE"
    } > "$s_tmp"
    # Deliberately NOT locked -- see commands/memory-auto-split.md's
    # SUBJECT-INDEX section: these are ordinary in-flight subject files, and
    # leaving them unlocked means a later /mempenny:memory-curate pass (or
    # nap) can finally archive/delete a RESOLVED subject, which pending.md's
    # own blanket curate-exemption previously made impossible.
    chmod 600 "$s_tmp"
    mv "$s_tmp" "$MEMORY_DIR/${ENTRY_FILE[$i]}"
    SHARD_FILES+=("${ENTRY_FILE[$i]}")
  done

  KEPT_TMP=$(mktemp "$MEMORY_DIR/.mempenny-autosplit-XXXXXXXX") || fail "mktemp failed"
  {
    sed -n "1,${SUBJ_PREAMBLE_END}p" "$TOPIC_FILE"
    printf '\n'
    for ((i = 0; i < N_ENTRIES; i++)); do
      printf -- '- [%s](%s)\n' "$(md_link_text "${ENTRY_HEADING_TEXT[$i]}")" "${ENTRY_FILE[$i]}"
    done
    if [ "$EXISTING_INDEX_START" -gt 0 ]; then
      sed -n "${EXISTING_INDEX_START},${TOTAL_LINES_FILE}p" "$TOPIC_FILE"
    fi
  } > "$KEPT_TMP"

else
  # ============================== PROSE-PEEL strategy (last resort) ==============================
  # Neither DATE nor SUBJECT-INDEX applied -- fewer than 2 (real) `## `
  # blocks and no date-only headings. Falls back to a position-based split,
  # direction DERIVED from datestamps in the file, never assumed either way.
  if [ "$FRONTMATTER_END" -ge "$((TOTAL_LINES_FILE - 1))" ]; then
    fail "$TOPIC_BASENAME has no peelable content outside its frontmatter -- a human should look at this file"
  fi

  # --- derive chronological direction from datestamps -- never assumed ---
  # First/last OCCURRENCE in file order (not "first line's date vs last
  # line's date" -- a line with no date at all is simply skipped by grep -o).
  # Day-granularity dates are preferred; month-only is the fallback only when
  # no full YYYY-MM-DD appears anywhere. ISO, zero-padded fields sort lexically
  # == chronologically, same trick used by the DATE strategy's own guard.
  BODY_START=$((FRONTMATTER_END + 1))
  # `|| true` on each: under `set -eo pipefail`, grep -oE finding ZERO matches
  # (routine and expected for a genuinely dateless file, not an error) would
  # otherwise kill the script right here -- before the emptiness is ever
  # checked below -- exactly the "grep -c ... || true" trap already guarded
  # against elsewhere in this file (FENCE_COUNT, is_even_fence_prefix).
  FIRST_DATE=$(tail -n "+$BODY_START" "$TOPIC_FILE" | { grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' || true; } | head -1)
  LAST_DATE=$(tail -n "+$BODY_START" "$TOPIC_FILE" | { grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' || true; } | tail -1)
  if [ -z "$FIRST_DATE" ] || [ -z "$LAST_DATE" ]; then
    FIRST_DATE=$(tail -n "+$BODY_START" "$TOPIC_FILE" | { grep -oE '[0-9]{4}-[0-9]{2}' || true; } | head -1)
    LAST_DATE=$(tail -n "+$BODY_START" "$TOPIC_FILE" | { grep -oE '[0-9]{4}-[0-9]{2}' || true; } | tail -1)
  fi
  if [ -z "$FIRST_DATE" ] || [ -z "$LAST_DATE" ]; then
    fail "$TOPIC_BASENAME has no heading structure (no ## YYYY-MM/YYYY-MM-DD, fewer than 2 ## subject blocks) and no detectable YYYY-MM-DD or YYYY-MM datestamp anywhere in its body -- cannot safely determine which end is oldest without guessing. Trim manually, or add explicit structure so DATE/SUBJECT-INDEX can apply instead."
  fi
  if [ "$FIRST_DATE" = "$LAST_DATE" ]; then
    fail "$TOPIC_BASENAME's first and last detected datestamp are both $FIRST_DATE -- a single distinct date gives no chronological direction to derive. Trim manually."
  fi
  if [[ "$FIRST_DATE" > "$LAST_DATE" ]]; then
    PROSE_DIRECTION="newest-first"
  else
    PROSE_DIRECTION="newest-last"
  fi

  if [ "$PROSE_DIRECTION" = "newest-last" ]; then
    # Oldest = PREFIX (top), newest = SUFFIX (bottom, kept live). Smallest CUT
    # (>= FRONTMATTER_END) such that the suffix (CUT+1..EOF) fits both
    # ceilings -- suffix size is non-increasing as CUT grows, so one forward
    # pass finds the minimum directly. Peeled range (page) is
    # (FRONTMATTER_END, CUT]; kept range is 1..FRONTMATTER_END plus
    # (CUT, TOTAL_LINES_FILE].
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
    done < <(tail -n "+$BODY_START" "$TOPIC_FILE" | awk '{ printf "%d\0", length($0) + 1 }')

    # Floor: always leave at least the file's last line live.
    if [ "$CUT" -ge "$TOTAL_LINES_FILE" ]; then
      CUT=$((TOTAL_LINES_FILE - 1))
    fi

    # Fence-safety nudge FORWARD (grows the page/prefix, shrinks the kept
    # suffix -- the ceiling-safe direction here, since KEPT=suffix must stay
    # under ceiling and shrinking it only ever helps). Bounded by the
    # "leave at least one line live" floor, not an unbounded search.
    while [ "$CUT" -lt "$((TOTAL_LINES_FILE - 1))" ] && ! is_even_fence_prefix "$CUT"; do
      CUT=$((CUT + 1))
    done
    is_even_fence_prefix "$CUT" || fail "no fence-safe split boundary found without shredding the entire file -- a human should look at $TOPIC_BASENAME's fenced code blocks"

    if [ "$CUT" -le "$FRONTMATTER_END" ]; then
      echo "SPLIT OK: nothing to split ($TOPIC_BASENAME has no peelable content once frontmatter and fence-safety are accounted for)"
      exit 0
    fi

    SHARD_RANGE_START=$((FRONTMATTER_END + 1)); SHARD_RANGE_END="$CUT"
    KEPT_TAIL_START=$((CUT + 1))
  else
    # newest-first: oldest = SUFFIX (bottom), newest = PREFIX (top, kept
    # live). Largest CUT (frontmatter through some line) such that the HEAD
    # (1..CUT, includes frontmatter) fits both ceilings -- the mirror image of
    # the branch above: grow the kept head as long as it still fits, stop the
    # instant the next line would push it over.
    CUT="$FRONTMATTER_END"
    cum_bytes="$FRONTMATTER_BYTES"
    cur_line="$FRONTMATTER_END"
    while IFS= read -r -d '' llen; do
      cur_line=$((cur_line + 1))
      candidate_bytes=$((cum_bytes + llen))
      if [ "$candidate_bytes" -le "$CEILING_BYTES" ] && [ "$cur_line" -le "$CEILING_LINES" ]; then
        cum_bytes="$candidate_bytes"
        CUT="$cur_line"
      else
        break
      fi
    done < <(tail -n "+$BODY_START" "$TOPIC_FILE" | awk '{ printf "%d\0", length($0) + 1 }')

    # Floor: always leave at least one line of head content live, even if that
    # alone is over ceiling (mirrors the DATE strategy's floor-tolerated case).
    if [ "$CUT" -le "$FRONTMATTER_END" ]; then
      CUT=$((FRONTMATTER_END + 1))
    fi

    # Fence-safety nudge BACKWARD (shrinks the kept head -- the ceiling-safe
    # direction here, since KEPT=head must stay under ceiling and shrinking it
    # only ever helps; growing it back toward the naive cut could reopen an
    # unclosed fence). Bounded by the same "leave at least one line live"
    # floor, not an unbounded search.
    while [ "$CUT" -gt "$((FRONTMATTER_END + 1))" ] && ! is_even_fence_prefix "$CUT"; do
      CUT=$((CUT - 1))
    done
    is_even_fence_prefix "$CUT" || fail "no fence-safe split boundary found without shredding the entire file -- a human should look at $TOPIC_BASENAME's fenced code blocks"

    if [ "$CUT" -ge "$TOTAL_LINES_FILE" ]; then
      echo "SPLIT OK: nothing to split ($TOPIC_BASENAME has no peelable content once frontmatter and fence-safety are accounted for)"
      exit 0
    fi

    SHARD_RANGE_START=$((CUT + 1)); SHARD_RANGE_END="$TOTAL_LINES_FILE"
    KEPT_HEAD_END="$CUT"
  fi

  TODAY=$(date -u +%Y-%m-%d)
  shard="$MEMORY_DIR/$STEM-archive-$TODAY.md"
  if [ -e "$shard" ] || [ -L "$shard" ]; then
    fail "shard collision: $(basename "$shard") already exists -- a split already ran today for $TOPIC_BASENAME. If the file is over ceiling again, this is a second genuine episode on the same day; resolve manually (rename the existing archive shard, or wait for tomorrow's date)."
  fi
  [[ "$shard" =~ $C1 ]] || fail "shard path fails C1: $shard"

  s_tmp=$(mktemp "$MEMORY_DIR/.mempenny-autosplit-XXXXXXXX") || fail "mktemp failed"
  { printf -- '---\ntype: %s\n---\n<!-- mempenny-lock -->\n' "$TOPIC_TYPE"
    sed -n "${SHARD_RANGE_START},${SHARD_RANGE_END}p" "$TOPIC_FILE"
  } > "$s_tmp"
  chmod 600 "$s_tmp"
  mv "$s_tmp" "$shard"
  SHARD_FILES+=("$(basename "$shard")")

  KEPT_TMP=$(mktemp "$MEMORY_DIR/.mempenny-autosplit-XXXXXXXX") || fail "mktemp failed"
  if [ "$PROSE_DIRECTION" = "newest-last" ]; then
    {
      if [ "$FRONTMATTER_END" -ge 1 ]; then sed -n "1,${FRONTMATTER_END}p" "$TOPIC_FILE"; fi
      sed -n "${KEPT_TAIL_START},${TOTAL_LINES_FILE}p" "$TOPIC_FILE"
    } > "$KEPT_TMP"
  else
    sed -n "1,${KEPT_HEAD_END}p" "$TOPIC_FILE" > "$KEPT_TMP"
  fi
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
# found verbatim somewhere in {every page + the kept/index remainder}. New
# SUBJECT-INDEX bullets are additions, not replacements of any source line,
# so this missing-only check permits them without weakening the guarantee.
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
if [ "$GRANULARITY" = "prose-peel" ]; then
  echo "PROSE_DIRECTION=$PROSE_DIRECTION"
fi
if [ "$GRANULARITY" = "subject-index" ]; then
  echo "SUBJECTS_SPLIT=${#SHARD_FILES[@]}"
fi
echo "SHARD_FILES_WRITTEN: $SHARD_LIST"
echo "BEFORE_BYTES=$BEFORE_BYTES"
echo "AFTER_BYTES=$AFTER_BYTES"
echo "AFTER_LINES=$AFTER_LINES"
