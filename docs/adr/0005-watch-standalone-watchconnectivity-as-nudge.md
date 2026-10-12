# 0005. Watch app is standalone; WatchConnectivity only as an optional nudge

- **Status**: Accepted
- **Date**: 2026-09-23 (recorded retroactively 2026-10-12)

## Context

The Watch must show the next shift even when no iPhone is nearby, so it
cannot depend on WatchConnectivity (which needs a reachable paired
phone). But a fresh change on one device should be noticed sooner on the
other when both are around.

## Decision

The Watch makes its own API call and has its own cache. WatchConnectivity
(`WatchConnectivityBridge`, iOS/watchOS only) is an explicit fast-path
supplement that signals "refresh now" together with a CloudKit-based
signal; it never relays data and nothing depends on it.

## Consequences

- The baseline works with no iPhone at all and degrades gracefully.
- Two refresh paths to reason about; hardware verification of the nudge
  is still pending (see [`../roadmap.md`](../roadmap.md) if raised).
- Details: [`../architecture.md`](../architecture.md) (Sync strategy,
  "Keep the Watch fresh").
