---
name: BlueTrail — always use short-lived auth tokens
description: Team convention: BlueTrail service accounts must use 1-hour JWT expiry; long-lived tokens are forbidden.
type: feedback
originSessionId: dddddddd-0000-0000-0000-000000000001
---
After a leaked credential incident in early 2026, the team adopted a hard rule: all service accounts
authenticating to `api.blueTrail.example.invalid` must request JWTs with a maximum 1-hour expiry.

Long-lived tokens (24 h or more) are forbidden regardless of environment. Rotation must be automated;
no manual token management in production.

**Decision owner:** Avery (security lead), ratified by the full team 2026-01-20.
