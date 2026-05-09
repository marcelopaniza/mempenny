---
name: BlueTrail — don't use fixed-interval polling
description: Fixed-interval retries on BlueTrail caused the thundering herd; switch to backoff.
type: feedback
last-updated: 2026-03-15
originSessionId: aaaaaaaa-0000-0000-0000-000000000002
---
After the March outage we identified fixed-interval polling as the root cause of the thundering herd on `api.blueTrail.example.invalid`. All callers retried every 5 s in sync, overwhelming the gateway.

Switch to exponential backoff. Parameters TBD — Avery to confirm.
