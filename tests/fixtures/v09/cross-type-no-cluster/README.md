# Fixture: cross-type-no-cluster

## Purpose

Two files about the same topic (BlueTrail authentication) but with different `type` values:
one is `feedback` (a team convention) and one is `project` (the implementation work). The files
are clearly related, but clustering across different types is not permitted.

## Files

| File | Type | Content |
|------|------|---------|
| `feedback_blueTrail_auth_tokens.md` | `feedback` | Convention: 1-hour JWT max, no long-lived tokens |
| `project_blueTrail_auth_refactor.md` | `project` | Delivery plan for the Vault-based rotation rollout |

## Expected v0.9 cluster output

- **Cluster formed:** NO
- **Action:** Both files remain independent; no cluster proposed, no merge, no dedupe.
- **Rationale:** The clustering rule requires files in a candidate cluster to share the same `type`.
  A `feedback` and a `project` file must never be clustered together, even when the subject is
  obviously related. The two serve structurally different roles: one is a permanent convention, the
  other is a time-bounded delivery plan. Merging them would blur that distinction.

## What would make a cluster form here

- Both files having the same `type` — e.g., both `project` or both `feedback`.
- Removing the type rule (a deliberate design change, not a bug fix).
