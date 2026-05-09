---
name: Orca project — technical approach
description: Architecture decisions for Orca, the Fenix pipeline replacement, covering streaming stack and schema choices.
type: project
originSessionId: bbbbbbbb-0000-0000-0000-000000000002
---
Orca replaces Fenix, the legacy batch pipeline, with a streaming architecture. The project goal is to
eliminate the 4-hour lag that Fenix's nightly batch window imposes.

**Architecture decisions:**
- Event bus: Kafka (managed, via `kafka.example.invalid`)
- Schema format: Avro with the company schema registry
- Processing layer: Flink jobs deployed on Kubernetes
- Output sinks: BigQuery (analytics) and Postgres (operational read models)

**Why not keep Fenix?** Fenix cannot be extended to sub-hour latency without a full rewrite anyway. The
team agreed it is cheaper to build Orca correctly than to patch Fenix.

**Open question:** Avery is evaluating whether Flink or ksqlDB better fits the team's skill set. Decision
expected by 2026-05-20.
