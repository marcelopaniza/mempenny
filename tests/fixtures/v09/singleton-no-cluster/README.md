# Fixture: singleton-no-cluster

## Purpose

A single `feedback`-type file. There is no second file to pair it with. A cluster requires at
least two candidate files — a singleton can never form one.

## Files

| File | Type | Content |
|------|------|---------|
| `feedback_orca_deployment_checklist.md` | `feedback` | Deployment gate: Jordan/Avery must approve smoke tests |

## Expected v0.9 cluster output

- **Cluster formed:** NO
- **Action:** File is left untouched; no cluster candidate is created.
- **Rationale:** Clustering is defined on pairs (or larger sets) of files. A solitary file has no
  peer to cluster with. The cluster-analysis subagent should skip it or pass it through as a
  standalone entry — it must not hallucinate a cluster or propose any action based on a single file
  alone.

## What would make a cluster form here

- Adding a second file to this directory that covers the same subject and same type.
- Note: simply adding an unrelated file would NOT create a cluster — topical overlap is also required.
