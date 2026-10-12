# 0008. Shift reminders as local notifications only

- **Status**: Accepted
- **Date**: 2026-09-02 (recorded retroactively 2026-10-12)

## Context

The Engelsystem API has no push or webhook mechanism, and running our own
push backend would conflict with the "no backend of our own" stance and
the privacy policy.

## Decision

Reminders are scheduled locally with `UNUserNotificationCenter` from the
loaded shift data (configurable lead time). No APNs, no server-side push.

## Consequences

- Reminders are only as fresh as the last sync; background sync
  mitigates this.
- Nothing about shifts ever leaves the device for notifications.
- Details: [`../features.md`](../features.md).
