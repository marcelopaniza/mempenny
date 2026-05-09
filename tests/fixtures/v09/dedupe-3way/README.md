# Fixture: dedupe-3way

## Purpose

Three `feedback`-type files about the same subject (BlueTrail retry strategy), written at different points
in time as the decision evolved. Content overlaps are high — later files supersede earlier ones.

## Files

| File | `last-updated` | Role |
|------|---------------|------|
| `feedback_blueTrail_retry_strategy_2026-04-01.md` | 2026-04-01 | Definitive decision with concrete parameters |
| `feedback_blueTrail_retry_strategy_2026-03-15.md` | 2026-03-15 | Interim note after outage, decision pending |
| `feedback_blueTrail_retry_strategy_2026-02-10.md` | 2026-02-10 | Earliest note, no conclusion |

## Expected v0.9 cluster output

- **Cluster type:** DEDUPE
- **Action:** Keep `feedback_blueTrail_retry_strategy_2026-04-01.md` (newest, contains the resolved
  decision). Archive `2026-03-15` and `2026-02-10` (superseded drafts).
- **Rationale:** All three files concern the same narrow subject. The content of the two older files is
  fully subsumed by the newest: the March file raised the problem without resolution; the February file
  had no conclusion at all. No contradictory facts — all three agree on the cause; only the newest
  provides the accepted fix. This is an unambiguous dedupe: near-duplicate content where only the
  timestamp and resolution state differ.

## What would make this NOT a DEDUPE cluster

- Any file containing a distinct, non-redundant insight not present in the newest file.
- File types differing (e.g., one becoming `project` type).
