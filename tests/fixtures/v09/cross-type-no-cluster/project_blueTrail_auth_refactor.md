---
name: BlueTrail auth refactor project
description: Project to replace hardcoded BlueTrail service-account credentials with automated short-lived JWT rotation.
type: project
originSessionId: dddddddd-0000-0000-0000-000000000002
---
The BlueTrail auth refactor project replaces all hardcoded long-lived service-account credentials with
automated JWT rotation using Vault's dynamic secrets engine.

**Scope:** All services calling `api.blueTrail.example.invalid` — currently 7 microservices.

**Milestones:**
- 2026-03-01 — Vault dynamic secrets engine configured (Jordan)
- 2026-04-01 — First 3 services migrated
- 2026-05-15 — All 7 services migrated; hardcoded credentials revoked

**Status (2026-05-01):** 5 of 7 services migrated. Two remaining: `billing-svc` and `report-exporter`.
