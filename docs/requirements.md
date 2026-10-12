# Requirements

Scope and boundaries of the Engelsystem Client: what the app is for, what
is in scope now, what must wait for backend support, and the implementation
order. Technical design lives in [`architecture.md`](architecture.md),
shipped behavior in [`features.md`](features.md), open work in
[`roadmap.md`](roadmap.md)/[`backlog.md`](backlog.md).

## Purpose of the app

Native Apple client app for [Engelsystem](https://github.com/engelsystem/engelsystem/)
(volunteer-management system for events, e.g. congresses). The app uses the
official REST API of the respective Engelsystem instance.

## Current scope (Phase 1 — read-only)

- View your own shifts
- Read news/announcements
- View profile, angel types, worklogs
- Local reminders (UserNotifications) before shift start, generated from the
  loaded shift data — **no** server push, since the API doesn't support that
- Multi-instance capable (multiple events/servers manageable at the same
  time, switching in Settings)
- Watch app: standalone (its own network call — WatchConnectivity, added
  2026-09-23, is only an optional fast-path nudge, never a data relay; see
  `docs/architecture.md`'s "Sync strategy"), shows only the next shift +
  complication
- Demo mode: try the app without a real Engelsystem server or API key
  (see "Demo mode" in [`architecture.md`](architecture.md))

## Phase 2 (later, requires backend extension — DO NOT implement now)

- Shift sign-up
- Create/edit shifts
- Do **not** prepare these features as disabled/hidden UI — build them only
  once the backend endpoint exists.

~~Send/receive private messages~~ **Implemented 2026-09-23** — see the
Messages feature in `docs/features.md` and the `/messages`
entry under API below. The backend endpoint this used to be blocked on
now exists (on a not-yet-merged server branch); the client-side GUI is
gated entirely behind a runtime capability probe
(`Instance.messagesSupported`) rather than the usual "wait for the
backend, then build" rule, since the feature had to work correctly
against instances that don't support it yet too — see "if the instance
doesn't offer the new interface, don't show the GUI" in the Messages
writeup.

## Watch app scope (deliberately minimal)

- Shows **only**: next shift (name, start, location) + complication
- No full shift catalog, no news on the Watch
- Its own API call (`GET /users/self/shifts`, filtered to the next
  upcoming shift)
- Local notification scheduling on the Watch too, for the next shift
- **Exception to "minimal": Settings has full parity with iOS** — at the
  user's explicit request, the Watch app supports the same instance
  management (switch/add/remove, update API key) and notification
  lead-time picker as the iOS Settings screen, including multi-instance
  switching (previously iOS-only). This was a deliberate scope decision,
  not scope creep: "minimal" governs which *data views* the Watch shows
  (still just the next shift, no catalog/news), not configuration. See
  [`features.md`](features.md) for how
  it's reached and built.


## Implementation order

1. ✅ Finish `EngelsystemClientKit` package + codegen setup
2. ✅ SwiftData models (`Instance`, `CachedShift`, `CachedNews`, `CachedUser`,
   `CachedWorklog`) incl. CloudKit configuration — models done, CloudKit
   wiring still open (see [`features.md`](features.md))
3. ✅ `APIClient` + `KeychainSyncStore`/`LocalKeychainStore`
4. ✅ iOS app: `InstanceSetup` feature (first runnable feature)
5. ✅ iOS app: Shifts / News / Profile / Settings
6. ✅ Watch app: `NextShiftView`, sync status display, fallback form
7. ✅ Watch complication
8. ✅ Demo mode (`DemoData` provider in `APIClient` + "Try Demo" entry
   point on `InstanceSetup`)
