---
name: Orca deployment checklist convention
description: Before any Orca release, Jordan must sign off the smoke-test suite results; no deploy without that approval.
type: feedback
originSessionId: eeeeeeee-0000-0000-0000-000000000001
---
After the v2.0 deployment that shipped with a broken event-deserialization path, the team adopted a
gate: no Orca release goes to production without Jordan's explicit sign-off on the smoke-test suite
results.

The smoke suite lives at `ci.example.invalid/orca/smoke` and must show 100% pass before Jordan approves.
Avery can stand in if Jordan is unavailable, but the approval step cannot be skipped.

This applies to all environments above staging (canary, production).
