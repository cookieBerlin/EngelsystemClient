# Release checklist (TestFlight / App Store)

Run top to bottom for every build. Identifiers and metadata:
[`app-store.md`](app-store.md); policy pages: [`privacy.md`](privacy.md),
[`support.md`](support.md).

## Before archiving

1. Working tree clean, `main` up to date.
2. `swift test` in `EngelsystemClientKit` green, plus a full Xcode build of
   the iOS app **and** the Watch app (`xcodebuild build -scheme …`) and the
   app test targets.
3. Bump `CURRENT_PROJECT_VERSION` for every upload; bump
   `MARKETING_VERSION` for a new release (both in the Xcode project).
4. Update [`CHANGELOG.md`](../CHANGELOG.md) (once it exists, D-09) and
   check [`privacy.md`](privacy.md) still matches the shipped data handling.

## Archive and upload

The signed-in Apple account lives in Xcode's GUI session: `xcodebuild -exportArchive`
from a terminal fails with "No Accounts", so **distribute from the Xcode Organizer**
(Window → Organizer → Archives → Distribute App → App Store Connect → Upload). A CLI
archive is fine for validating that the project builds and embeds the Watch app and
complication — see "Build number" in [`app-store.md`](app-store.md) for the number gotcha.

1. Scheme `EngelsystemClient`, destination *Any iOS Device*.
2. Product → Archive → Organizer → Distribute App → App Store Connect →
   Upload. The Watch app and complication are embedded.
3. Export compliance: only standard HTTPS/Keychain/CloudKit encryption →
   exempt; `ITSAppUsesNonExemptEncryption = NO` is set in
   `EngelsystemClient-Info.plist`, so no per-build question.

## App Store screenshots

Run `Scripts/screenshots.sh` (see "Screenshots" in [`app-store.md`](app-store.md)) and upload `Screenshots/iphone/en/`,
`Screenshots/ipad/en/` and `Screenshots/watch/en/` in App Store Connect before the first App Store submission, and again
whenever the UI or the demo data changes visibly.

## TestFlight

- **Internal testing**: no Beta App Review; testers are App Store Connect
  users. Available once the build finishes processing.
- **External testing**: requires Beta App Review. Provide Beta App
  Description, Feedback Email (`EngelsystemClient@cuccato.net`), Privacy
  Policy URL and Support URL (both on
  `https://cookieberlin.github.io/EngelsystemClient/`). Reviewers have no
  Engelsystem account: tell them to use **"Try Demo Mode"** on the setup
  screen (see Demo mode in [`architecture.md`](architecture.md)).

## After release

- Tag the commit (`v<MARKETING_VERSION>`), move the finished entries from
  [`roadmap.md`](roadmap.md)/[`backlog.md`](backlog.md) into
  [`features.md`](features.md).

## Draft texts for TestFlight Test Information

- **Beta App Description**: "Engelsystem Client is an unofficial companion app for the
  Engelsystem volunteer-management system used by events like the Chaos Communication
  Congress. See your own shifts, news, locations and messages, get local reminders before a
  shift, and glance at your next shift on Apple Watch. Please test: adding your event's
  server with an API key, shift reminders, the Watch app and complication, and pull-to-refresh.
  No server? Tap 'Try Demo Mode' on the first screen."
- **What to Test** (per build): "First TestFlight build: setup and Demo Mode, Shifts/News/Profile/
  Locations/Messages, reminders, Watch app and complication, Settings (including Export
  Diagnostics)."
- **Beta App Review notes**: "No account is needed. On the first screen tap 'Try Demo Mode' — it
  uses built-in sample data and makes no network requests. A real Engelsystem instance and API key
  are only needed to test against an actual server."
- **Feedback Email**: `EngelsystemClient@cuccato.net`; **Privacy Policy URL**:
  `https://cookieberlin.github.io/EngelsystemClient/privacy`; **Support**:
  `https://cookieberlin.github.io/EngelsystemClient/support`.
