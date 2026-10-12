# 0006. Messages are live-only and gated by a runtime capability probe

- **Status**: Accepted
- **Date**: 2026-09-23 (recorded retroactively 2026-10-12)

## Context

`/messages` is the API's first read/write resource and exists only on a
not-yet-merged server branch, so many instances will not support it. A
local cache would require reconciling offline writes with the server.

## Decision

- No SwiftData cache and no sync service: every call hits the network.
- `Instance.messagesSupported` (default `false`, CloudKit-synced) decides
  whether the Messages UI exists at all ("if the instance doesn't offer
  the interface, don't show the GUI"). It is probed by a single
  `GET /messages` during the regular sync, distinguishing a missing route
  from a real 404 by the response body.
- iOS only; no Messages on the Watch.

## Consequences

- No offline reading or sending of messages; much simpler first version.
- The probe re-runs periodically, so later server support is picked up.
- Details: [`../features.md`](../features.md), [`../architecture.md`](../architecture.md) (API).
