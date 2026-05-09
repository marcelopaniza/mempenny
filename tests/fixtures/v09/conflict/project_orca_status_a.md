---
name: Orca project status — v2.3 shipped
description: Orca reached v2.3 in production on 2026-03-01; Fenix decommissioned.
type: project
originSessionId: cccccccc-0000-0000-0000-000000000001
---
As of 2026-03-01, Orca v2.3 is in production. Fenix has been fully decommissioned. The cut-over went
smoothly with zero data loss confirmed by Jordan.

The team decided to use **Flink** as the stream-processing layer. Avery completed the evaluation on
2026-02-15 and selected Flink over ksqlDB due to better support for stateful joins.

Current throughput in production: **12 k events/s**, comfortably above the 10 k target.
