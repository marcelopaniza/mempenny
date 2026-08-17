#!/usr/bin/env bash
# MemPenny -- auto-split fixture tests (hooks/auto-split.sh).
#
# Unlike run-smoke.sh (structural fixture checks only, no live logic), this
# harness actually EXERCISES hooks/auto-split.sh end-to-end against synthetic
# fixture directories generated fresh under mktemp -- never a real memory dir,
# never anything committed to the repo. auto-split.sh is pure, deterministic
# bash (no LLM in the loop), so unlike the conservation checks documented in
# run-smoke.sh's own footer, this one CAN be asserted automatically, here,
# with no model and no Claude Code host required.
#
# Covers: conservation (every original line survives in shard/page+kept,
# checked independently of the script's own self-reported TOTAL_MISSING), the
# live file ending up at-or-under ceiling (or provably as-reduced-as-the-
# content-allows at the documented floor), a real backup existing and
# matching, idempotency (a second run is a no-op, byte-for-byte), the
# fence-safety nudge (a fenced block is proven to land whole in one output,
# never torn), both DATE-strategy granularities (## YYYY-MM and
# ## YYYY-MM-DD), SUBJECT-INDEX (the primary strategy for a real, ##-
# structured pending.md -- realistic fixture, nested ### handling, unlocked
# detail pages, incremental re-split after new subjects are prepended, the
# empty-slug fallback, and the deterministic collision suffix), PROSE-PEEL's
# direction-derivation (both directions, plus its own fail-closed paths), and
# every other fail-closed path (locks, an ineligible topic name, a symlinked
# target, a same-day shard collision).
#
# Usage: ./tests/run-autosplit.sh

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/hooks/auto-split.sh"
WORKROOT=$(mktemp -d "${TMPDIR:-/tmp}/mempenny-autosplit-test-XXXXXXXX")

pass=0
fail=0
ok()  { echo "  ok    $*"; pass=$((pass + 1)); }
bad() { echo "  FAIL  $*"; fail=$((fail + 1)); }

norm_lines() { sed 's/^[[:space:]]*//; s/[[:space:]]*$//' "$1" | grep -v '^$'; }

# Independent conservation re-check -- does NOT trust the script's own
# TOTAL_MISSING=0 self-report. Re-derives it from scratch against the
# pre-split snapshot every case keeps on the side.
assert_conservation() {
  local orig="$1"; shift
  local haystack missing=0
  haystack=$(mktemp)
  for f in "$@"; do norm_lines "$f" >>"$haystack"; done
  while IFS= read -r line; do
    grep -qFx -- "$line" "$haystack" || { missing=$((missing + 1)); echo "    MISSING: $line"; }
  done < <(norm_lines "$orig")
  rm -f "$haystack"
  [ "$missing" -eq 0 ]
}

run_split() { bash "$SCRIPT" "$1" "$2" "$3" "$4" "$5"; }

repeat_line() { local n="$1" text="$2" i; for ((i = 1; i <= n; i++)); do printf '%s\n' "${text//__N__/$i}"; done; }

echo "MemPenny auto-split -- fixture-driven behavioral tests"
echo "(workroot: $WORKROOT)"
echo

# =============================================================================
echo "=== case: prose pending.md, NEWEST-FIRST (the real, verified production convention -- the motivating scenario) ==="
D="$WORKROOT/prose_newest_first"; mkdir -p "$D"
{
  printf -- '---\ntype: pending\n---\n\n'
  for n in $(seq 1 650); do
    d=$(date -u -d "2026-08-13 - $((n / 20)) days" +%Y-%m-%d 2>/dev/null || date -u -v-"$((n / 20))"d -jf "%Y-%m-%d" "2026-08-13" +%Y-%m-%d)
    printf -- 'Pending item %05d (%s): in-flight work, newest items PREPENDED at the top -- verified real pending.md convention.\n' "$n" "$d"
  done
} > "$D/pending.md"
ORIG="$WORKROOT/prose.orig.md"; cp "$D/pending.md" "$ORIG"
BACKUP="$WORKROOT/prose.backup"; cp -a "$D" "$BACKUP"
FIRST_LINE_ORIG=$(sed -n '5p' "$ORIG")   # first content line (right after frontmatter) -- newest, must stay live
LAST_LINE_ORIG=$(tail -n1 "$ORIG")       # last line -- oldest, must end up in the shard

OUT=$(run_split "$D" "pending.md" "pending" 25600 200); RC=$?
echo "$OUT" | sed 's/^/    /'
[ "$RC" -eq 0 ] && echo "$OUT" | grep -q "^SCRIPT_OK$" && ok "exit 0 + SCRIPT_OK" || bad "expected SCRIPT_OK/exit0, got rc=$RC"
echo "$OUT" | grep -q "^PROSE_DIRECTION=newest-first$" && ok "direction correctly derived as newest-first from the file's own datestamps" || bad "direction not derived as newest-first: $OUT"
echo "$OUT" | grep -q "^TOTAL_MISSING=0$" && ok "script's own conservation check: 0 missing" || bad "script reported missing lines"

SHARD=$(find "$D" -maxdepth 1 -name 'pending-archive-*.md' -type f)
[ -n "$SHARD" ] && ok "shard file created: $(basename "$SHARD")" || bad "no shard file found"
assert_conservation "$ORIG" "$D/pending.md" "$SHARD" && ok "(a) independent conservation check: every original line found in shard+kept" || bad "(a) conservation check FAILED"

AFTER_BYTES=$(wc -c <"$D/pending.md" | tr -d ' '); AFTER_LINES=$(wc -l <"$D/pending.md" | tr -d ' ')
{ [ "$AFTER_BYTES" -le 25600 ] && [ "$AFTER_LINES" -le 200 ]; } && ok "(b) live file now under ceiling ($AFTER_BYTES B / $AFTER_LINES lines)" || bad "(b) live file still over ceiling ($AFTER_BYTES B / $AFTER_LINES lines)"

{ [ -d "$BACKUP" ] && diff -q "$BACKUP/pending.md" "$ORIG" >/dev/null 2>&1; } && ok "(c) backup exists and matches the pre-split original" || bad "(c) backup missing or mismatched"

grep -q '<!-- mempenny-lock -->' "$SHARD" && ok "shard is lock-marked (frozen)" || bad "shard missing lock marker"
grep -q '^type: pending$' "$SHARD" && ok "shard frontmatter carries type: pending" || bad "shard frontmatter wrong/missing"

# The critical direction assertion: for a newest-first file, the OLDEST content
# (the file's LAST line) must be sharded, and the NEWEST content (the file's
# FIRST content line) must stay live -- exactly backwards from a naive
# head-is-oldest assumption, and exactly what the verified real pending.md
# convention requires.
grep -qFx -- "$FIRST_LINE_ORIG" "$D/pending.md" && ok "newest (first/top) line still live, undisturbed" || bad "newest top line missing from the live file"
grep -qFx -- "$FIRST_LINE_ORIG" "$SHARD" 2>/dev/null && bad "newest top line leaked into the shard" || ok "newest top line correctly absent from the shard"
grep -qFx -- "$LAST_LINE_ORIG" "$SHARD" && ok "oldest (last/bottom) line correctly sharded" || bad "oldest bottom line missing from the shard"
grep -qFx -- "$LAST_LINE_ORIG" "$D/pending.md" 2>/dev/null && bad "oldest bottom line leaked into the live file" || ok "oldest bottom line correctly absent from the live file"

SUM_1=$(sha256sum "$D/pending.md" "$SHARD" | sha256sum)
OUT2=$(run_split "$D" "pending.md" "pending" 25600 200)
echo "$OUT2" | grep -q "nothing to split" && ok "(d) idempotent: second run is a clean no-op" || bad "(d) second run was not a no-op: $OUT2"
SUM_2=$(sha256sum "$D/pending.md" "$SHARD" | sha256sum)
[ "$SUM_1" = "$SUM_2" ] && ok "(d) re-run touched nothing on disk" || bad "(d) re-run modified files"
echo

# =============================================================================
echo "=== case: prose pending.md, NEWEST-LAST (append-style -- the other direction the algorithm must also derive correctly) ==="
D="$WORKROOT/prose_newest_last"; mkdir -p "$D"
{
  printf -- '---\ntype: pending\n---\n\n'
  for n in $(seq 1 650); do
    d=$(date -u -d "2026-06-01 + $((n / 20)) days" +%Y-%m-%d 2>/dev/null || date -u -v+"$((n / 20))"d -jf "%Y-%m-%d" "2026-06-01" +%Y-%m-%d)
    printf -- 'Pending item %05d (%s): in-flight work, appended at the bottom.\n' "$n" "$d"
  done
} > "$D/pending.md"
ORIG="$WORKROOT/prose_last.orig.md"; cp "$D/pending.md" "$ORIG"
FIRST_LINE_ORIG=$(sed -n '5p' "$ORIG")   # oldest -- must be sharded
LAST_LINE_ORIG=$(tail -n1 "$ORIG")       # newest -- must stay live

OUT=$(run_split "$D" "pending.md" "pending" 25600 200); RC=$?
echo "$OUT" | sed 's/^/    /'
[ "$RC" -eq 0 ] && echo "$OUT" | grep -q "^SCRIPT_OK$" && ok "exit 0 + SCRIPT_OK" || bad "expected SCRIPT_OK/exit0, got rc=$RC"
echo "$OUT" | grep -q "^PROSE_DIRECTION=newest-last$" && ok "direction correctly derived as newest-last" || bad "direction not derived as newest-last: $OUT"

SHARD=$(find "$D" -maxdepth 1 -name 'pending-archive-*.md' -type f)
assert_conservation "$ORIG" "$D/pending.md" "$SHARD" && ok "conservation holds for the newest-last direction" || bad "conservation FAILED for newest-last"
grep -qFx -- "$LAST_LINE_ORIG" "$D/pending.md" && ok "newest (last/bottom) line still live, undisturbed" || bad "newest bottom line missing from the live file"
grep -qFx -- "$FIRST_LINE_ORIG" "$SHARD" && ok "oldest (first/top) line correctly sharded" || bad "oldest top line missing from the shard"
echo

# =============================================================================
echo "=== case: prose (newest-first) with a fenced code block straddling the naive cut point ==="
D="$WORKROOT/prose_fence"; mkdir -p "$D"
{
  printf -- '---\ntype: pending\n---\n\n'
  repeat_line 13 "Recent filler line __N__ (2026-08-16), newer in-flight content near the top."
  printf -- '```bash\n'
  repeat_line 30 "echo 'fenced content line __N__ that must never be split mid-block'"
  printf -- '```\n'
  repeat_line 20 "Early filler line __N__ (2026-07-01), old content near the bottom."
} > "$D/pending.md"
ORIG="$WORKROOT/fence.orig.md"; cp "$D/pending.md" "$ORIG"

# Ceiling chosen so the NAIVE (fence-unaware) cut point would land inside the
# fence: verified interactively while designing this fixture (line 18 =
# "```bash", line 49 = closing "```"; the largest kept-head that fits under
# 1800 bytes without any fence-awareness lands at line 30, inside the block).
OUT=$(run_split "$D" "pending.md" "pending" 1800 200); RC=$?
echo "$OUT" | sed 's/^/    /'
[ "$RC" -eq 0 ] && echo "$OUT" | grep -q "^SCRIPT_OK$" && ok "split succeeded" || bad "split failed unexpectedly rc=$RC"

SHARD=$(find "$D" -maxdepth 1 -name 'pending-archive-*.md' -type f)
KEPT_FC=$(grep -c '^```' "$D/pending.md" || true); SHARD_FC=$(grep -c '^```' "$SHARD" || true)
[ $((KEPT_FC % 2)) -eq 0 ] && ok "kept file has balanced fences ($KEPT_FC)" || bad "kept file has UNBALANCED fences ($KEPT_FC)"
[ $((SHARD_FC % 2)) -eq 0 ] && ok "shard has balanced fences ($SHARD_FC)" || bad "shard has UNBALANCED fences ($SHARD_FC)"

if grep -q '^```bash$' "$SHARD" 2>/dev/null; then FENCE_HOME="$SHARD"; OTHER="$D/pending.md"; else FENCE_HOME="$D/pending.md"; OTHER="$SHARD"; fi
if grep -q "fenced content line 1 that" "$FENCE_HOME" && grep -q "fenced content line 30 that" "$FENCE_HOME" && ! grep -q "fenced content line 1 that" "$OTHER"; then
  ok "entire fenced block (open + all 30 lines + close) landed in one file, never torn"
else
  bad "fenced block was split across shard/kept -- fence-safety nudge did not work"
fi
assert_conservation "$ORIG" "$D/pending.md" "$SHARD" && ok "conservation holds across the fence-straddling split" || bad "conservation FAILED on the fence case"
echo

# =============================================================================
echo "=== case: log-topic (worklog.md) stuck entirely in the open year -- ## YYYY-MM ==="
D="$WORKROOT/log_open_year"; mkdir -p "$D"
{
  printf -- '---\ntype: worklog\n---\n\n'
  for m in 2026-08 2026-07 2026-06 2026-05 2026-04 2026-03 2026-02 2026-01; do
    printf '## %s\n\n' "$m"
    for i in 1 2 3 4 5 6 7 8; do printf -- '- **%s-%02d** — did a substantial piece of work, item %d, with enough narrative detail to add up across the year.\n' "$m" "$i" "$i"; done
    printf '\n'
  done
} > "$D/worklog.md"
ORIG="$WORKROOT/log.orig.md"; cp "$D/worklog.md" "$ORIG"

OUT=$(run_split "$D" "worklog.md" "worklog" 2500 200); RC=$?
echo "$OUT" | sed 's/^/    /'
[ "$RC" -eq 0 ] && echo "$OUT" | grep -q "^SCRIPT_OK$" && ok "split succeeded" || bad "split failed rc=$RC"
echo "$OUT" | grep -q "GRANULARITY=month" && ok "detected month granularity" || bad "wrong/missing granularity"

SHARDS=$(find "$D" -maxdepth 1 -name 'worklog-2026-*.md' -type f | sort)
[ -n "$SHARDS" ] && ok "at least one month shard written ($(echo "$SHARDS" | wc -l | tr -d ' '))" || bad "no month shards written"
echo "$SHARDS" | grep -q 'worklog-2026-08.md' && bad "newest month (2026-08) was incorrectly sharded" || ok "newest month (2026-08) correctly stayed live"
grep -q '## 2026-08' "$D/worklog.md" && ok "## 2026-08 heading still present live" || bad "newest month heading missing from live file"

BAD_SHARD=0
for s in $SHARDS; do
  grep -q '<!-- mempenny-lock -->' "$s" || { bad "shard $(basename "$s") missing lock marker"; BAD_SHARD=1; }
  grep -q '^type: worklog$' "$s" || { bad "shard $(basename "$s") wrong frontmatter"; BAD_SHARD=1; }
done
[ "$BAD_SHARD" -eq 0 ] && ok "all shards lock-marked with correct frontmatter"

if echo "$SHARDS" | grep -q 'worklog-2026-01.md'; then
  grep -q '2026-01-0' "$D/worklog.md" 2>/dev/null && bad "January content leaked into the live file" || ok "January content correctly absent from the live file"
fi
# shellcheck disable=SC2086 # intentional word-splitting -- $SHARDS is a newline-joined
# list of shard paths (H1-safe, space-free filenames) meant to expand to multiple args.
assert_conservation "$ORIG" "$D/worklog.md" $SHARDS && ok "conservation holds for the open-year log-topic split" || bad "conservation FAILED for log-topic split"

OUT2=$(run_split "$D" "worklog.md" "worklog" 2500 200)
echo "$OUT2" | grep -q "nothing to split" && ok "idempotent re-run is a clean no-op" || bad "re-run was not a clean no-op: $OUT2"
echo

# =============================================================================
echo "=== case: log-topic (decisions.md) stuck in open year -- ## YYYY-MM-DD day headings ==="
D="$WORKROOT/log_open_year_days"; mkdir -p "$D"
{
  printf -- '---\ntype: decisions\n---\n\n'
  for day_off in $(seq 0 15) $(seq 26 36); do
    day=$(date -u -d "2026-08-16 - ${day_off} days" +%Y-%m-%d 2>/dev/null || date -u -v-"${day_off}"d -jf "%Y-%m-%d" "2026-08-16" +%Y-%m-%d)
    printf '## %s\n\n### decision made on %s — why X over Y\n\nRationale text for the decision made on %s, long enough to accumulate real size across many days.\n\n' "$day" "$day" "$day"
  done
} > "$D/decisions.md"
ORIG="$WORKROOT/logdays.orig.md"; cp "$D/decisions.md" "$ORIG"

OUT=$(run_split "$D" "decisions.md" "decisions" 1200 200); RC=$?
echo "$OUT" | sed 's/^/    /'
[ "$RC" -eq 0 ] && echo "$OUT" | grep -q "^SCRIPT_OK$" && ok "split succeeded" || bad "split failed rc=$RC"
echo "$OUT" | grep -q "GRANULARITY=day" && ok "detected day granularity" || bad "wrong/missing granularity"

SHARDS=$(find "$D" -maxdepth 1 -name 'decisions-2026-*.md' -type f | sort)
[ -n "$SHARDS" ] && ok "day shard(s) written ($(echo "$SHARDS" | wc -l | tr -d ' '))" || bad "no day shards written"
echo "$SHARDS" | grep -q 'decisions-2026-08-16.md' && bad "newest day (08-16) incorrectly sharded" || ok "newest day (2026-08-16) correctly stayed live"
grep -q '## 2026-08-16' "$D/decisions.md" && ok "newest day heading still live" || bad "newest day heading missing"
# shellcheck disable=SC2086 # intentional word-splitting, same as above
assert_conservation "$ORIG" "$D/decisions.md" $SHARDS && ok "conservation holds for day-granularity split" || bad "conservation FAILED for day split"
echo

# =============================================================================
echo "=== case: already under ceiling -- must be a clean no-op ==="
D="$WORKROOT/under_ceiling"; mkdir -p "$D"
printf -- '---\ntype: pending\n---\n\nOne small in-flight item, nowhere near the ceiling.\n' > "$D/pending.md"
SUM_BEFORE=$(sha256sum "$D/pending.md")
OUT=$(run_split "$D" "pending.md" "pending" 25600 200); RC=$?
echo "$OUT" | sed 's/^/    /'
[ "$RC" -eq 0 ] && echo "$OUT" | grep -q "nothing to split" && ok "reported a clean no-op" || bad "unexpected behavior on an under-ceiling file: rc=$RC"
SUM_AFTER=$(sha256sum "$D/pending.md")
[ "$SUM_BEFORE" = "$SUM_AFTER" ] && ok "file byte-identical, zero writes" || bad "file was modified despite being under ceiling"
[ -z "$(find "$D" -maxdepth 1 -name '*-archive-*.md' -o -name 'pending-2*')" ] && ok "no shard files created" || bad "unexpected shard file(s) created"
echo

# =============================================================================
echo "=== case: single-period log-topic over ceiling -- nothing OLDER exists, must no-op ==="
D="$WORKROOT/single_period"; mkdir -p "$D"
{
  printf -- '---\ntype: worklog\n---\n\n## 2026-08\n\n'
  repeat_line 900 "- **2026-08-01** — item __N__ in the only month this file has ever had."
} > "$D/worklog.md"
SUM_BEFORE=$(sha256sum "$D/worklog.md"); BEFORE_BYTES=$(wc -c <"$D/worklog.md")
OUT=$(run_split "$D" "worklog.md" "worklog" 25600 200); RC=$?
echo "$OUT" | sed 's/^/    /'
[ "$BEFORE_BYTES" -gt 25600 ] && ok "sanity: fixture genuinely starts over ceiling ($BEFORE_BYTES B)" || bad "fixture setup bug: not actually over ceiling"
[ "$RC" -eq 0 ] && echo "$OUT" | grep -q "nothing to split" && ok "correctly refuses to force-split the only period" || bad "should have no-op'd: rc=$RC"
SUM_AFTER=$(sha256sum "$D/worklog.md")
[ "$SUM_BEFORE" = "$SUM_AFTER" ] && ok "file untouched" || bad "file was modified despite nothing older to peel"
echo

# =============================================================================
echo "=== case: charter.md WITH dates (paired with pending.md under the same curate-exemption -- proves the mechanism is shared, not pending.md-specific) ==="
D="$WORKROOT/charter"; mkdir -p "$D"
{
  printf -- '---\ntype: charter\n---\n\n'
  for n in $(seq 1 500); do
    d=$(date -u -d "2026-01-01 + $((n / 15)) days" +%Y-%m-%d 2>/dev/null || date -u -v+"$((n / 15))"d -jf "%Y-%m-%d" "2026-01-01" +%Y-%m-%d)
    printf -- 'Requirement %05d (%s): the artifact must continue to satisfy this requirement, appended after the previous one as scope grew over time.\n' "$n" "$d"
  done
} > "$D/charter.md"
ORIG="$WORKROOT/charter.orig.md"; cp "$D/charter.md" "$ORIG"
OUT=$(run_split "$D" "charter.md" "charter" 25600 200); RC=$?
echo "$OUT" | sed 's/^/    /'
[ "$RC" -eq 0 ] && echo "$OUT" | grep -q "^SCRIPT_OK$" && ok "dated charter.md split succeeds (same mechanism as pending.md)" || bad "charter.md split failed rc=$RC"
echo "$OUT" | grep -q "^PROSE_DIRECTION=newest-last$" && ok "direction correctly derived for charter.md too" || bad "direction not derived correctly for charter.md: $OUT"
SHARD=$(find "$D" -maxdepth 1 -name 'charter-archive-*.md' -type f)
assert_conservation "$ORIG" "$D/charter.md" "$SHARD" && ok "conservation holds for charter.md" || bad "conservation FAILED for charter.md"
echo

# =============================================================================
echo "=== case: charter.md with NO dates -- the realistic shape (goal/requirements prose, no chronology) -- must fail closed, not guess ==="
D="$WORKROOT/charter_dateless"; mkdir -p "$D"
{
  printf -- '---\ntype: charter\n---\n\n'
  repeat_line 400 "Requirement __N__: the artifact must satisfy this requirement, no datestamp anywhere in this file to establish chronology."
} > "$D/charter.md"
SUM_BEFORE=$(sha256sum "$D/charter.md")
OUT=$(run_split "$D" "charter.md" "charter" 25600 200); RC=$?
echo "$OUT" | sed 's/^/    /'
{ [ "$RC" -ne 0 ] && echo "$OUT" | grep -q "^SPLIT FAILED:" && echo "$OUT" | grep -qi "datestamp"; } && ok "refuses to guess on a dateless, headingless file -- fails closed rather than picking an arbitrary direction" || bad "did not correctly refuse the dateless case (rc=$RC): $OUT"
SUM_AFTER=$(sha256sum "$D/charter.md")
[ "$SUM_BEFORE" = "$SUM_AFTER" ] && ok "dateless charter.md left completely untouched" || bad "dateless charter.md was modified!"
echo

# =============================================================================
echo "=== case: prose with a single distinct datestamp -- no direction to derive, must also fail closed ==="
D="$WORKROOT/prose_single_date"; mkdir -p "$D"
{
  printf -- '---\ntype: pending\n---\n\n'
  repeat_line 400 "Pending item __N__ (2026-08-16): every line carries the exact same date, so there is no chronological direction to derive."
} > "$D/pending.md"
SUM_BEFORE=$(sha256sum "$D/pending.md")
OUT=$(run_split "$D" "pending.md" "pending" 25600 200); RC=$?
echo "$OUT" | sed 's/^/    /'
{ [ "$RC" -ne 0 ] && echo "$OUT" | grep -q "^SPLIT FAILED:" && echo "$OUT" | grep -qi "no chronological direction"; } && ok "refuses to guess when first and last datestamp are identical" || bad "did not correctly refuse the single-date case (rc=$RC): $OUT"
SUM_AFTER=$(sha256sum "$D/pending.md")
[ "$SUM_BEFORE" = "$SUM_AFTER" ] && ok "single-date pending.md left completely untouched" || bad "single-date pending.md was modified!"
echo

# =============================================================================
echo "=== case: floor tolerated -- newest period alone still exceeds ceiling ==="
D="$WORKROOT/floor_case"; mkdir -p "$D"
{
  printf -- '---\ntype: worklog\n---\n\n## 2026-08\n\n'
  repeat_line 60 "- **2026-08-01** — a fairly long line of narrative content padding out the still-open month well past the test ceiling on its own, item __N__."
  printf '\n## 2026-07\n\n'
  repeat_line 10 "- **2026-07-01** — an older item from last month, item __N__."
} > "$D/worklog.md"
ORIG="$WORKROOT/floor.orig.md"; cp "$D/worklog.md" "$ORIG"
BEFORE_BYTES=$(wc -c <"$D/worklog.md")

OUT=$(run_split "$D" "worklog.md" "worklog" 1000 5000); RC=$?
echo "$OUT" | sed 's/^/    /'
[ "$RC" -eq 0 ] && echo "$OUT" | grep -q "^SCRIPT_OK$" && ok "split still runs even though the floor alone exceeds ceiling" || bad "unexpected result rc=$RC"
[ -f "$D/worklog-2026-07.md" ] && ok "older month (07) still peeled off" || bad "older month was not peeled"
grep -q '## 2026-08' "$D/worklog.md" && ok "newest month (08) stays live even though it alone is over ceiling" || bad "newest month wrongly removed"
AFTER_BYTES=$(wc -c <"$D/worklog.md")
[ "$AFTER_BYTES" -lt "$BEFORE_BYTES" ] && ok "still a real, meaningful reduction ($BEFORE_BYTES -> $AFTER_BYTES B)" || bad "no reduction happened"
assert_conservation "$ORIG" "$D/worklog.md" "$D/worklog-2026-07.md" && ok "conservation holds at the floor-tolerated boundary" || bad "conservation FAILED at the floor boundary"
echo

# =============================================================================
echo "=== failure-mode: file-level lock marker refuses the split ==="
D="$WORKROOT/locked_file"; mkdir -p "$D"
{ printf -- '---\ntype: pending\n---\n<!-- mempenny-lock -->\n'; repeat_line 400 "padding line __N__ to push this file over the ceiling."; } > "$D/pending.md"
SUM_BEFORE=$(sha256sum "$D/pending.md")
OUT=$(run_split "$D" "pending.md" "pending" 25600 200); RC=$?
echo "$OUT" | sed 's/^/    /'
{ [ "$RC" -ne 0 ] && echo "$OUT" | grep -q "^SPLIT FAILED:" && echo "$OUT" | grep -qi "locked"; } && ok "refused a locked file, no write" || bad "did not correctly refuse a locked file (rc=$RC)"
SUM_AFTER=$(sha256sum "$D/pending.md")
[ "$SUM_BEFORE" = "$SUM_AFTER" ] && ok "locked file untouched" || bad "locked file was modified!"
echo

echo "=== failure-mode: folder-level .mempenny-lock refuses the split ==="
D="$WORKROOT/locked_folder"; mkdir -p "$D"
touch "$D/.mempenny-lock"
{ printf -- '---\ntype: pending\n---\n\n'; repeat_line 400 "padding line __N__."; } > "$D/pending.md"
SUM_BEFORE=$(sha256sum "$D/pending.md")
OUT=$(run_split "$D" "pending.md" "pending" 25600 200); RC=$?
echo "$OUT" | sed 's/^/    /'
{ [ "$RC" -ne 0 ] && echo "$OUT" | grep -q "^SPLIT FAILED:" && echo "$OUT" | grep -qi "lock"; } && ok "refused a lock-marked folder, no write" || bad "did not correctly refuse a lock-marked folder (rc=$RC)"
SUM_AFTER=$(sha256sum "$D/pending.md")
[ "$SUM_BEFORE" = "$SUM_AFTER" ] && ok "file in a locked folder untouched" || bad "file was modified despite the folder lock!"
echo

echo "=== failure-mode: ineligible topic file (traps.md -- belongs to curate) ==="
D="$WORKROOT/ineligible"; mkdir -p "$D"
{ printf -- '---\ntype: traps\n---\n\n'; repeat_line 400 "padding line __N__."; } > "$D/traps.md"
OUT=$(run_split "$D" "traps.md" "traps" 25600 200); RC=$?
echo "$OUT" | sed 's/^/    /'
{ [ "$RC" -ne 0 ] && echo "$OUT" | grep -q "not one of the 5 auto-split-eligible files" && echo "$OUT" | grep -qi "memory-curate"; } && ok "refused traps.md and pointed at curate" || bad "did not correctly refuse traps.md (rc=$RC)"
echo

echo "=== failure-mode: symlinked topic file is refused (F-M2) ==="
D="$WORKROOT/symlink_case"; mkdir -p "$D"
REAL="$WORKROOT/symlink_target.md"
{ printf -- '---\ntype: pending\n---\n\n'; repeat_line 400 "padding line __N__."; } > "$REAL"
ln -s "$REAL" "$D/pending.md"
OUT=$(run_split "$D" "pending.md" "pending" 25600 200); RC=$?
echo "$OUT" | sed 's/^/    /'
{ [ "$RC" -ne 0 ] && echo "$OUT" | grep -qi "symlink"; } && ok "refused a symlinked topic file" || bad "did not correctly refuse a symlink (rc=$RC)"
echo

echo "=== edge case: second genuine over-ceiling episode the same day -- fails closed, no data loss ==="
D="$WORKROOT/same_day_collision"; mkdir -p "$D"
{
  printf -- '---\ntype: pending\n---\n\n'
  for n in $(seq 1 700); do
    d=$(date -u -d "2026-06-01 + $((n / 20)) days" +%Y-%m-%d 2>/dev/null || date -u -v+"$((n / 20))"d -jf "%Y-%m-%d" "2026-06-01" +%Y-%m-%d)
    printf -- 'Pending item %05d (%s): filler appended after the previous item.\n' "$n" "$d"
  done
} > "$D/pending.md"
run_split "$D" "pending.md" "pending" 25600 200 | grep -q "^SCRIPT_OK$" && ok "first split of the day succeeds" || bad "first split unexpectedly failed"
SNAPSHOT_SHARD=$(sha256sum "$D"/pending-archive-*.md)
for n in $(seq 701 1400); do
  d=$(date -u -d "2026-08-16 + $(((n - 700) / 20)) days" +%Y-%m-%d 2>/dev/null || date -u -v+"$(((n - 700) / 20))"d -jf "%Y-%m-%d" "2026-08-16" +%Y-%m-%d)
  printf -- 'Second-episode pending item %05d (%s): more filler appended later the same day.\n' "$n" "$d"
done >>"$D/pending.md"
OUT=$(run_split "$D" "pending.md" "pending" 25600 200); RC=$?
echo "$OUT" | sed 's/^/    /'
{ [ "$RC" -ne 0 ] && echo "$OUT" | grep -qi "collision"; } && ok "second same-day episode fails closed (documented limitation, not silent overwrite/data loss)" || bad "second same-day episode did not fail closed as designed"
AFTER_SHARD=$(sha256sum "$D"/pending-archive-*.md)
[ "$SNAPSHOT_SHARD" = "$AFTER_SHARD" ] && ok "first archive shard untouched by the failed second attempt" || bad "first archive shard was modified/corrupted"
echo

# =============================================================================
# SUBJECT-INDEX strategy -- the primary strategy for a real, ##-structured
# pending.md (verified structure: frontmatter, a preamble, dozens of
# top-level `## ` subject blocks, newest at the top, occasional nested `### `
# detail, occasional fenced code). "Over ceiling -> the main file becomes the
# INDEX, subjects become PAGES" -- see docs/memory-taxonomy-design.md SS4b.
echo "=== case: SUBJECT-INDEX, realistic pending.md shape (frontmatter + preamble + ## blocks, one fenced, newest-first) ==="
D="$WORKROOT/subject_index"; mkdir -p "$D"
{
  printf -- '---\ntype: pending\n---\n\n'
  printf -- 'Short preamble line describing the project context.\n\n'
  printf -- '## \360\237\237\242 2026-08-16 \342\200\224 SHIP THE FEATURE\n\nWork on the feature is progressing well.\n\n### sub detail heading\n\nNested detail that must stay inside its ## parent, never its own split unit.\n\n'
  printf -- '## \360\237\237\247 2026-08-14 \342\200\224 SUPERSEDED PLAN\n\nThis plan was superseded by a later decision -- exactly the kind of RESOLVED subject that pending.md'"'"'s old blanket curate-exemption used to shield from ever being triaged.\n\n'
  printf -- '## \360\237\237\242 2026-08-10 \342\200\224 SECRET REGISTRY BUILT + VERIFIED (docs/SECRET-REGISTRY.md)\n\nRotation completed and verified.\n\n```bash\necho verifying secret rotation\n```\n\n'
  for n in $(seq 1 30); do
    printf -- '## \360\237\237\242 2026-07-%02d \342\200\224 filler subject number %d with descriptive words\n\n' "$((n % 28 + 1))" "$n"
    # Each block's BODY (not the bullet count) is what needs to push the
    # PRE-split file past the real 25600 B ceiling, while each block's
    # HEADING (the only thing that becomes an index bullet) stays short --
    # so the POST-split index still comfortably fits the same real ceiling,
    # both checked against the one real constant, no separate test-only
    # ceiling to keep in sync with the (b) assertion below.
    repeat_line 6 "Filler body line __N__ for subject $n, padding this block's body well past what a single short bullet will cost once collapsed into the index."
    printf '\n'
  done
} > "$D/pending.md"
ORIG="$WORKROOT/subject_index.orig.md"; cp "$D/pending.md" "$ORIG"
BACKUP="$WORKROOT/subject_index.backup"; cp -a "$D" "$BACKUP"

OUT=$(run_split "$D" "pending.md" "pending" 25600 200); RC=$?
echo "$OUT" | sed 's/^/    /'
[ "$RC" -eq 0 ] && echo "$OUT" | grep -q "^SCRIPT_OK$" && ok "exit 0 + SCRIPT_OK" || bad "expected SCRIPT_OK/exit0, got rc=$RC"
echo "$OUT" | grep -q "^GRANULARITY=subject-index$" && ok "correctly chose SUBJECT-INDEX over prose-peel (## structure detected)" || bad "did not choose subject-index: $OUT"
echo "$OUT" | grep -q "^SUBJECTS_SPLIT=33$" && ok "all 33 top-level ## blocks became pages (3 named + 30 filler)" || bad "unexpected SUBJECTS_SPLIT count: $OUT"
echo "$OUT" | grep -q "^TOTAL_MISSING=0$" && ok "script's own conservation check: 0 missing" || bad "script reported missing lines"

DETAIL_FILES=$(find "$D" -maxdepth 1 -name 'pending-[0-9]*.md' -type f | sort)
DETAIL_COUNT=$(printf '%s\n' "$DETAIL_FILES" | grep -c . || true)
[ "$DETAIL_COUNT" -eq 33 ] && ok "33 detail files on disk" || bad "expected 33 detail files, found $DETAIL_COUNT"

# (b) live file = frontmatter + preamble + index ONLY, and under ceiling.
AFTER_BYTES=$(wc -c <"$D/pending.md" | tr -d ' '); AFTER_LINES=$(wc -l <"$D/pending.md" | tr -d ' ')
{ [ "$AFTER_BYTES" -le 25600 ] && [ "$AFTER_LINES" -le 200 ]; } && ok "(b) live index file under ceiling ($AFTER_BYTES B / $AFTER_LINES lines)" || bad "(b) live file still over ceiling ($AFTER_BYTES B / $AFTER_LINES lines)"
grep -q '^## ' "$D/pending.md" && bad "a raw ## heading survived in the live file -- it should be 100% index now" || ok "live file has zero ## headings left -- fully converted to an index"
BULLET_COUNT=$(grep -c '^- \[' "$D/pending.md" || true)
[ "$BULLET_COUNT" -eq 33 ] && ok "live file is a clean, scannable map: exactly one bullet per subject (33)" || bad "expected 33 index bullets, found $BULLET_COUNT"
grep -q 'Short preamble line' "$D/pending.md" && ok "preamble survived verbatim in the live/index file" || bad "preamble missing from the live file"

# Each block verbatim in its own correctly-named detail file.
grep -rl 'SHIP THE FEATURE' "$D"/pending-*.md >/dev/null 2>&1 && ok "'SHIP THE FEATURE' block landed in its own detail file" || bad "'SHIP THE FEATURE' block missing from any detail file"
SHIP_FILE=$(grep -l 'SHIP THE FEATURE' "$D"/pending-*.md)
grep -q 'sub detail heading' "$SHIP_FILE" && ok "nested ### stayed inside its ## parent's detail file" || bad "nested ### separated from its parent"
SECRET_FILE=$(grep -l 'SECRET REGISTRY BUILT' "$D"/pending-*.md)
FC=$(grep -c '^```' "$SECRET_FILE" || true)
[ $((FC % 2)) -eq 0 ] && [ "$FC" -eq 2 ] && ok "fenced block landed intact (balanced) in its own detail file" || bad "fenced block unbalanced/missing in its detail file ($FC)"
grep -q '^name: ' "$SECRET_FILE" && grep -q '^description: "' "$SECRET_FILE" && grep -qE '^\s*type: pending$' "$SECRET_FILE" && ok "detail file frontmatter shape correct (name/description/metadata.type)" || bad "detail file frontmatter shape wrong"
grep -q 'mempenny-lock' "$SECRET_FILE" && bad "detail file is locked -- SUBJECT-INDEX pages must stay unlocked (triage-ability is the point)" || ok "detail file correctly left UNLOCKED"

# (a) conservation, independently re-derived.
# shellcheck disable=SC2086
assert_conservation "$ORIG" "$D/pending.md" $DETAIL_FILES && ok "(a) independent conservation check: every original line found in index+pages" || bad "(a) conservation check FAILED"

# (c) backup exists.
{ [ -d "$BACKUP" ] && diff -q "$BACKUP/pending.md" "$ORIG" >/dev/null 2>&1; } && ok "(c) backup exists and matches the pre-split original" || bad "(c) backup missing or mismatched"

# (d) idempotent re-run.
SUM_1=$(find "$D" -maxdepth 1 -name '*.md' | sort | xargs sha256sum | sha256sum)
OUT2=$(run_split "$D" "pending.md" "pending" 25600 200)
echo "$OUT2" | grep -q "nothing to split" && ok "(d) idempotent: second run is a clean no-op (all-bullets index is small by construction)" || bad "(d) second run was not a no-op: $OUT2"
SUM_2=$(find "$D" -maxdepth 1 -name '*.md' | sort | xargs sha256sum | sha256sum)
[ "$SUM_1" = "$SUM_2" ] && ok "(d) re-run touched nothing on disk" || bad "(d) re-run modified files"
echo

# =============================================================================
echo "=== case: SUBJECT-INDEX, prepend NEW blocks then re-split -- only the new ones split, existing pages untouched ==="
# Reuses the already-split $D from above. Force a real split with a small
# ceiling (the real 25600 ceiling would never trip on just 1-2 new bullets'
# worth of growth) so the "only new blocks split" code path is exercised.
PRE_EXISTING_DETAIL=$(find "$D" -maxdepth 1 -name 'pending-[0-9]*.md' -type f | sort)
PRE_EXISTING_SUM=$(printf '%s\n' "$PRE_EXISTING_DETAIL" | xargs sha256sum)
PRE_EXISTING_COUNT=$(printf '%s\n' "$PRE_EXISTING_DETAIL" | grep -c . || true)

NEWBLOCK=$(mktemp)
printf -- '## \360\237\237\242 2026-08-17 \342\200\224 BRAND NEW SUBJECT A\n\nFresh content A.\n\n## \360\237\237\242 2026-08-17 \342\200\224 BRAND NEW SUBJECT B\n\nFresh content B.\n\n' > "$NEWBLOCK"
awk -v newfile="$NEWBLOCK" '
  /^- \[/ && !inserted { while ((getline line < newfile) > 0) print line; inserted=1 }
  { print }
' "$D/pending.md" > "$D/pending.md.tmp" && mv "$D/pending.md.tmp" "$D/pending.md"
rm -f "$NEWBLOCK"

OUT=$(run_split "$D" "pending.md" "pending" 500 200); RC=$?
echo "$OUT" | sed 's/^/    /'
[ "$RC" -eq 0 ] && echo "$OUT" | grep -q "^SCRIPT_OK$" && ok "re-split succeeds" || bad "re-split failed rc=$RC"
echo "$OUT" | grep -q "^SUBJECTS_SPLIT=2$" && ok "only the 2 NEW blocks were split (not all 35)" || bad "wrong subject count on re-split: $OUT"

AFTER_DETAIL_COUNT=$(find "$D" -maxdepth 1 -name 'pending-[0-9]*.md' -type f | wc -l | tr -d ' ')
[ "$AFTER_DETAIL_COUNT" -eq "$((PRE_EXISTING_COUNT + 2))" ] && ok "detail file count grew by exactly 2 ($PRE_EXISTING_COUNT -> $AFTER_DETAIL_COUNT)" || bad "detail file count wrong: $PRE_EXISTING_COUNT -> $AFTER_DETAIL_COUNT"
AFTER_EXISTING_SUM=$(printf '%s\n' "$PRE_EXISTING_DETAIL" | xargs sha256sum)
[ "$PRE_EXISTING_SUM" = "$AFTER_EXISTING_SUM" ] && ok "all pre-existing detail pages byte-identical, untouched by the re-split" || bad "a pre-existing detail page was modified by the re-split"
grep -q 'BRAND NEW SUBJECT A' "$D"/pending-3*.md 2>/dev/null && ok "new subject numbered continuing from the existing max (30s), no collision with 01-33" || bad "new subject numbering collided with or reused an existing NN"
BULLET_COUNT_2=$(grep -c '^- \[' "$D/pending.md" || true)
[ "$BULLET_COUNT_2" -eq 35 ] && ok "live index now has 35 bullets: 2 new (first) + 33 pre-existing (unchanged, in place)" || bad "expected 35 bullets after re-split, found $BULLET_COUNT_2"
FIRST_BULLET=$(sed -n '/^- \[/p' "$D/pending.md" | head -1)
printf '%s' "$FIRST_BULLET" | grep -q 'BRAND NEW SUBJECT A' && ok "new bullets correctly inserted first (newest-first ordering preserved)" || bad "new bullets not in the expected newest-first position"
echo

# =============================================================================
echo "=== case: SUBJECT-INDEX, stripped-to-empty slug falls back to NN alone ==="
D="$WORKROOT/subject_empty_slug"; mkdir -p "$D"
{
  printf -- '---\ntype: pending\n---\n\n'
  printf -- '## \360\237\237\242 2026-08-16 \342\200\224 A REAL SUBJECT WITH WORDS\n\nBody one.\n\n'
  printf -- '## \360\237\216\211\360\237\216\212 2026-08-05\n\nA heading that is only emoji plus a bare date -- must slugify to empty and fall back to the ordinal alone, never an invalid or empty filename.\n\n'
} > "$D/pending.md"
ORIG="$WORKROOT/subject_empty_slug.orig.md"; cp "$D/pending.md" "$ORIG"
OUT=$(run_split "$D" "pending.md" "pending" 200 200); RC=$?
echo "$OUT" | sed 's/^/    /'
[ "$RC" -eq 0 ] && echo "$OUT" | grep -q "^SCRIPT_OK$" && ok "split succeeds on the empty-slug fixture" || bad "split failed rc=$RC"
[ -f "$D/pending-02.md" ] && ok "empty-slug subject correctly named just '<topic>-NN.md' (pending-02.md), no dangling hyphen or empty component" || bad "empty-slug fallback filename missing/wrong -- expected pending-02.md"
[[ "$(basename "$D/pending-02.md")" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*\.md$ ]] && ok "fallback filename passes the H1 filename regex" || bad "fallback filename fails H1"
DETAIL2=$(find "$D" -maxdepth 1 -name 'pending-0*.md')
# shellcheck disable=SC2086
assert_conservation "$ORIG" "$D/pending.md" $DETAIL2 && ok "conservation holds for the empty-slug case" || bad "conservation FAILED for empty-slug case"
echo

# =============================================================================
echo "=== case: SUBJECT-INDEX, two subjects that slugify to IDENTICAL text -- disambiguated by NN, neither lost ==="
# Design note (not in the original spec, worked out while testing it): a
# literal filename COLLISION, as in "the freshly computed candidate for a NEW
# block matches a file already on disk", is structurally unreachable through
# this script's normal entrypoint -- NN always continues from
# (highest NN already on disk) + 1, so a fresh candidate can never equal an
# already-used one; any pre-existing file shaped like a real detail page is,
# by the same glob that generates real candidates, always counted in that
# scan and therefore always skipped past. Confirmed directly: pre-seeding the
# exact name a fresh run would "naturally" pick doesn't collide at all --
# EXISTING_MAX_NN simply picks up the seed file and the real block gets the
# next number instead (proven interactively while diagnosing this test; the
# -2/-3 fallback in hooks/auto-split.sh remains as defense-in-depth for a
# scenario this codebase already disclaims -- concurrent/racing invocations
# -- not because it's reachable from any single run's own disk state).
# What IS both realistic and directly testable: two DIFFERENT subjects whose
# headings slugify to the SAME text (a very plausible real occurrence --
# near-duplicate or re-titled subjects). NN uniqueness must disambiguate them
# into two distinct files with neither one's content lost.
D="$WORKROOT/subject_dup_slug"; mkdir -p "$D"
{
  printf -- '---\ntype: pending\n---\n\n'
  printf -- '## \360\237\237\242 2026-08-16 \342\200\224 Ship The Feature!!!\n\nBody one -- the newer of the two near-duplicate headings.\n\n'
  printf -- '## \360\237\237\242 2026-08-14 --- SHIP the feature???\n\nBody two -- an older, differently-punctuated subject that slugifies to the same text as the one above.\n\n'
} > "$D/pending.md"
ORIG="$WORKROOT/subject_dup_slug.orig.md"; cp "$D/pending.md" "$ORIG"

OUT=$(run_split "$D" "pending.md" "pending" 150 150); RC=$?
echo "$OUT" | sed 's/^/    /'
[ "$RC" -eq 0 ] && echo "$OUT" | grep -q "^SCRIPT_OK$" && ok "split succeeds with two identically-sluggable headings" || bad "split failed rc=$RC"
echo "$OUT" | grep -q "^SUBJECTS_SPLIT=2$" && ok "both near-duplicate subjects were split, neither dropped or merged" || bad "expected 2 subjects split: $OUT"
DUP_FILES=$(find "$D" -maxdepth 1 -name 'pending-0*-ship-the-feature*.md' | sort)
DUP_COUNT=$(printf '%s\n' "$DUP_FILES" | grep -c . || true)
[ "$DUP_COUNT" -eq 2 ] && ok "two distinct files, disambiguated by NN alone (same slug, different NN)" || bad "expected 2 distinct same-slug files, found $DUP_COUNT: $DUP_FILES"
grep -l 'Body one' "$D"/pending-0*.md >/dev/null 2>&1 && ok "first subject's body present in its own file" || bad "first subject's body missing"
grep -l 'Body two' "$D"/pending-0*.md >/dev/null 2>&1 && ok "second subject's body present in its own file" || bad "second subject's body missing"
# shellcheck disable=SC2086
assert_conservation "$ORIG" "$D/pending.md" $DUP_FILES && ok "conservation holds for the duplicate-slug case" || bad "conservation FAILED for the duplicate-slug case"
echo

echo "=== unit-check: the collision-suffix loop itself is correct in isolation ==="
# hooks/auto-split.sh's own candidate-vs-disk collision loop, extracted
# verbatim in miniature, run directly against a directory that DOES already
# hold the exact candidate name -- proving the LOOP mechanism is correct even
# though (per the design note above) NN-continuation means the full script
# never actually needs it on any real single-run input.
D="$WORKROOT/collision_unit"; mkdir -p "$D"
touch "$D/x-01-foo.md" "$D/x-01-foo-2.md"
candidate="x-01-foo"; suffix=1; final="$candidate"
while [ -e "$D/$final.md" ] || [ -L "$D/$final.md" ]; do
  suffix=$((suffix + 1))
  final="$candidate-$suffix"
done
[ "$final" = "x-01-foo-3" ] && ok "collision loop correctly walks past -1 (implicit) and -2 to land on the first free name (-3)" || bad "collision loop landed on the wrong name: $final"
echo

echo "=== summary ==="
echo "checked=$((pass + fail))  pass=$pass  fail=$fail"
if [ "$fail" -ne 0 ]; then
  echo "TEST RUN: FAILED"
  echo "(workroot kept for inspection: $WORKROOT)"
  exit 1
fi
echo "TEST RUN: ALL PASSED"
rm -rf "$WORKROOT"
exit 0
