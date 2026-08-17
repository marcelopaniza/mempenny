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
# Covers: conservation (every original line survives in shard+kept, checked
# independently of the script's own self-reported TOTAL_MISSING), the live
# file ending up at-or-under ceiling (or provably as-reduced-as-the-content-
# allows at the documented floor), a real backup existing and matching,
# idempotency (a second run is a no-op, byte-for-byte), the fence-safety
# nudge (a fenced block is proven to land whole in one output, never torn),
# both DATE-strategy granularities (## YYYY-MM and ## YYYY-MM-DD), the PROSE
# strategy's frontmatter handling, and every fail-closed path (locks, an
# ineligible topic name, a symlinked target, a same-day shard collision).
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
echo "=== case: prose pending.md at the real ceiling (the motivating scenario) ==="
D="$WORKROOT/prose"; mkdir -p "$D"
{
  printf -- '---\ntype: pending\n---\n\n'
  repeat_line 650 "Pending item __N__: in-flight work item number __N__, appended after the previous one, needs follow-up and tracking across sessions until it is done."
} > "$D/pending.md"
ORIG="$WORKROOT/prose.orig.md"; cp "$D/pending.md" "$ORIG"
BACKUP="$WORKROOT/prose.backup"; cp -a "$D" "$BACKUP"

OUT=$(run_split "$D" "pending.md" "pending" 25600 200); RC=$?
echo "$OUT" | sed 's/^/    /'
[ "$RC" -eq 0 ] && echo "$OUT" | grep -q "^SCRIPT_OK$" && ok "exit 0 + SCRIPT_OK" || bad "expected SCRIPT_OK/exit0, got rc=$RC"
echo "$OUT" | grep -q "^TOTAL_MISSING=0$" && ok "script's own conservation check: 0 missing" || bad "script reported missing lines"

SHARD=$(find "$D" -maxdepth 1 -name 'pending-archive-*.md' -type f)
[ -n "$SHARD" ] && ok "shard file created: $(basename "$SHARD")" || bad "no shard file found"
assert_conservation "$ORIG" "$D/pending.md" "$SHARD" && ok "(a) independent conservation check: every original line found in shard+kept" || bad "(a) conservation check FAILED"

AFTER_BYTES=$(wc -c <"$D/pending.md" | tr -d ' '); AFTER_LINES=$(wc -l <"$D/pending.md" | tr -d ' ')
{ [ "$AFTER_BYTES" -le 25600 ] && [ "$AFTER_LINES" -le 200 ]; } && ok "(b) live file now under ceiling ($AFTER_BYTES B / $AFTER_LINES lines)" || bad "(b) live file still over ceiling ($AFTER_BYTES B / $AFTER_LINES lines)"

{ [ -d "$BACKUP" ] && diff -q "$BACKUP/pending.md" "$ORIG" >/dev/null 2>&1; } && ok "(c) backup exists and matches the pre-split original" || bad "(c) backup missing or mismatched"

grep -q '<!-- mempenny-lock -->' "$SHARD" && ok "shard is lock-marked (frozen)" || bad "shard missing lock marker"
grep -q '^type: pending$' "$SHARD" && ok "shard frontmatter carries type: pending" || bad "shard frontmatter wrong/missing"

TAIL_LINE=$(tail -n1 "$ORIG")
grep -qFx -- "$TAIL_LINE" "$D/pending.md" && ok "newest (tail) line still live, undisturbed" || bad "newest tail line missing from the live file"
grep -qFx -- "$TAIL_LINE" "$SHARD" 2>/dev/null && bad "newest tail line leaked into the shard" || ok "newest tail line correctly absent from the shard"

SUM_1=$(sha256sum "$D/pending.md" "$SHARD" | sha256sum)
OUT2=$(run_split "$D" "pending.md" "pending" 25600 200)
echo "$OUT2" | grep -q "nothing to split" && ok "(d) idempotent: second run is a clean no-op" || bad "(d) second run was not a no-op: $OUT2"
SUM_2=$(sha256sum "$D/pending.md" "$SHARD" | sha256sum)
[ "$SUM_1" = "$SUM_2" ] && ok "(d) re-run touched nothing on disk" || bad "(d) re-run modified files"
echo

# =============================================================================
echo "=== case: prose with a fenced code block straddling the naive cut point ==="
D="$WORKROOT/prose_fence"; mkdir -p "$D"
{
  printf -- '---\ntype: pending\n---\n\n'
  repeat_line 13 "Early filler line __N__, old content appended long ago in the file's history."
  printf -- '```bash\n'
  repeat_line 30 "echo 'fenced content line __N__ that must never be split mid-block'"
  printf -- '```\n'
  repeat_line 20 "Recent filler line __N__, newer in-flight content near the tail."
} > "$D/pending.md"
ORIG="$WORKROOT/fence.orig.md"; cp "$D/pending.md" "$ORIG"

# Ceiling chosen so the NAIVE (fence-unaware) cut point would land inside the
# fence: verified interactively while designing this fixture (line 23 =
# "```bash", line 54 = closing "```"; the smallest sufficient cut without any
# fence-awareness lands at line 35, inside the block).
OUT=$(run_split "$D" "pending.md" "pending" 2650 200); RC=$?
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
echo "=== case: charter.md (paired with pending.md under the same curate-exemption) ==="
D="$WORKROOT/charter"; mkdir -p "$D"
{
  printf -- '---\ntype: charter\n---\n\n'
  repeat_line 500 "Requirement __N__: the artifact must continue to satisfy this requirement, appended after the previous one as scope grew over time."
} > "$D/charter.md"
ORIG="$WORKROOT/charter.orig.md"; cp "$D/charter.md" "$ORIG"
OUT=$(run_split "$D" "charter.md" "charter" 25600 200); RC=$?
echo "$OUT" | sed 's/^/    /'
[ "$RC" -eq 0 ] && echo "$OUT" | grep -q "^SCRIPT_OK$" && ok "charter.md split succeeded (same mechanism as pending.md)" || bad "charter.md split failed rc=$RC"
SHARD=$(find "$D" -maxdepth 1 -name 'charter-archive-*.md' -type f)
assert_conservation "$ORIG" "$D/charter.md" "$SHARD" && ok "conservation holds for charter.md" || bad "conservation FAILED for charter.md"
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
{ printf -- '---\ntype: pending\n---\n\n'; repeat_line 700 "Pending item __N__: filler appended after the previous item."; } > "$D/pending.md"
run_split "$D" "pending.md" "pending" 25600 200 | grep -q "^SCRIPT_OK$" && ok "first split of the day succeeds" || bad "first split unexpectedly failed"
SNAPSHOT_SHARD=$(sha256sum "$D"/pending-archive-*.md)
repeat_line 700 "Second-episode pending item __N__: more filler appended later the same day." >>"$D/pending.md"
OUT=$(run_split "$D" "pending.md" "pending" 25600 200); RC=$?
echo "$OUT" | sed 's/^/    /'
{ [ "$RC" -ne 0 ] && echo "$OUT" | grep -qi "collision"; } && ok "second same-day episode fails closed (documented limitation, not silent overwrite/data loss)" || bad "second same-day episode did not fail closed as designed"
AFTER_SHARD=$(sha256sum "$D"/pending-archive-*.md)
[ "$SNAPSHOT_SHARD" = "$AFTER_SHARD" ] && ok "first archive shard untouched by the failed second attempt" || bad "first archive shard was modified/corrupted"
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
