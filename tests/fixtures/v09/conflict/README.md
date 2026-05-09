# Fixture: conflict

## Purpose

Two `project`-type files about the same project (Orca) with direct factual contradictions. Both
carry the same `as of` date (2026-03-01), making it impossible to dismiss one as simply older. The
contradictions span version number, production status, technology choice, and deployment state.

## Files

| File | Claims |
|------|--------|
| `project_orca_status_a.md` | Orca v2.3 is in **production**; Fenix **decommissioned**; team chose **Flink** |
| `project_orca_status_b.md` | Orca v2.1 is in **staging**; Fenix **still live**; team chose **ksqlDB** |

## Contradictions (explicit)

1. Version number: v2.3 vs v2.1
2. Deployment stage: production vs staging
3. Fenix status: decommissioned vs live in production
4. Technology decision: Flink vs ksqlDB (both attributed to Avery on 2026-02-15)
5. Throughput: 12 k events/s (live) vs 8 k events/s (still under test)

## Expected v0.9 cluster output

- **Cluster type:** FLAG (conflict)
- **Action:** Surface the contradiction to the user. Do NOT auto-merge, do NOT archive either file, do
  NOT silently discard one. Present both conflicting claims side-by-side and ask the user to resolve.
- **Rationale:** The cluster subagent must never auto-merge when factual claims disagree. Merging
  would silently embed false information into the user's memory. The safe action is always to flag
  and defer to the user.

## What would make this NOT a FLAG

- If one file were clearly older (different `last-updated`) and the newer file superseded all claims —
  that pattern would be DEDUPE, not FLAG.
- If the files covered different subjects entirely — then no cluster would form at all.
