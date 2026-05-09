---
name: Orca project status — v2.1 in staging
description: Orca is at v2.1 in staging as of 2026-03-01; Fenix still live in production.
type: project
originSessionId: cccccccc-0000-0000-0000-000000000002
---
As of 2026-03-01, Orca v2.1 is deployed to staging. Fenix is still handling 100% of production traffic.
Production cut-over is targeted for 2026-04-15, pending sign-off from the infra team.

The team decided to use **ksqlDB** as the stream-processing layer. Avery completed the evaluation on
2026-02-15 and selected ksqlDB over Flink because the team's SQL skills lower the operational overhead.

Current staging throughput: **8 k events/s** — load tests still running to reach the 10 k target.
