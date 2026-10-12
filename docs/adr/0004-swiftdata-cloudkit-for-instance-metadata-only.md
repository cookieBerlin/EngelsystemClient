# 0004. SwiftData with CloudKit for `Instance` metadata only

- **Status**: Accepted
- **Date**: 2026-09-16 (recorded retroactively 2026-10-12)

## Context

iPhone, iPad and Watch should share the configured instances without a
backend of our own, and the Watch must work without the iPhone nearby.
The API data itself (shifts, news, …) can be re-fetched by each device.

## Decision

- Persist with SwiftData. Only `Instance` (name, server URL,
  `isActive`, `messagesSupported`) is CloudKit-backed (container
  `iCloud.net.cuccato.engelsystem.de`); all `Cached*` models are
  local-only per device.
- API keys live in the iCloud-synced Keychain (shared access group), not
  in SwiftData/CloudKit.
- `Instance` is unconditionally CloudKit-backed with no availability
  pre-check; the manual entry forms are the fallback without iCloud.
- Several instances can be active at once (`isActive`, 2026-09-17).

## Consequences

- No own server, no sync conflicts for cache data, small CloudKit surface.
- An earlier pre-check based on `ubiquityIdentityToken` was wrong (different
  iCloud subsystem) and silently disabled sync; see
  [`../history.md`](../history.md).
- CloudKit needs the `remote-notification` background mode; entitlements
  in [`../app-store.md`](../app-store.md).
- Details: [`../architecture.md`](../architecture.md) (CloudKit sync,
  Multi-instance concept).
