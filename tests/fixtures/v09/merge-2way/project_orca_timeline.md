---
name: Orca project — timeline and milestones
description: Delivery schedule for the Orca data-pipeline rewrite, with milestone dates and owners.
type: project
originSessionId: bbbbbbbb-0000-0000-0000-000000000001
---
Orca is a rewrite of the legacy Fenix data pipeline. Target: replace Fenix in production by 2026-Q3.

**Milestones:**
- 2026-05-15 — schema design finalized (owner: Jordan)
- 2026-06-01 — ingestion layer deployed to staging
- 2026-07-15 — load tests pass at 10 k events/s
- 2026-08-01 — Fenix traffic cut over to Orca in production
- 2026-08-15 — Fenix decommissioned

**Risks:** Jordan flagged that the 2026-06-01 staging date depends on sign-off from the infra team on
the new Kafka cluster. If sign-off slips, the whole timeline shifts by at least two weeks.
