# Fixture: merge-2way

## Purpose

Two `project`-type files about the same project (Orca) from different angles. They share the same
subject, named entities (Jordan, Avery, Fenix, Orca), and goal — but one covers timeline and the other
covers technical approach. Neither is a strict subset of the other: each has unique, non-redundant
content. They cover the same subject from complementary angles, and the specific facts are complementary.

## Files

| File | Focus |
|------|-------|
| `project_orca_timeline.md` | Milestones, dates, cut-over plan, infra risk |
| `project_orca_technical_approach.md` | Stack choices, architecture rationale, open Flink/ksqlDB question |

## Expected v0.9 cluster output

- **Cluster type:** MERGE
- **Action:** Propose a merged `project_orca.md` that combines the milestone table and the architecture
  decisions into a single coherent file. Both source files get archived after the merged file is written.
- **Rationale:** Same project, same type, high topical overlap, no contradictions. A reader of either
  file alone has an incomplete picture; together they form a single complete project memory.

## What would make this NOT a MERGE cluster

- A factual contradiction between the two files (e.g., timeline file says Flink, approach file says
  Spark — that would flip to FLAG).
- File types diverging (one becoming `feedback`).
- One file expanding into a completely different sub-project, eliminating the complementary overlap.
