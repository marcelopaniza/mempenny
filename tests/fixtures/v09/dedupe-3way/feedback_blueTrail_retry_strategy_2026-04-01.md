---
name: BlueTrail retry strategy — use exponential backoff
description: After the March incident, team agreed to use exponential backoff with jitter on all BlueTrail API calls; fixed-interval polling caused a thundering herd.
type: feedback
last-updated: 2026-04-01
originSessionId: aaaaaaaa-0000-0000-0000-000000000001
---
BlueTrail API calls must use exponential backoff with jitter. Fixed-interval retry loops triggered a thundering herd during the March 2026 outage — 40 clients all retried at the same second.

**Rule:** base delay 500 ms, multiplier 2, cap 30 s, ±25 % jitter. Apply to every call to `api.blueTrail.example.invalid`.

**Decision owner:** Avery (platform lead), 2026-04-01.
