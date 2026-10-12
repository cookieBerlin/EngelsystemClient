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

1. Scheme `EngelsystemClient`, destination *Any iOS Device*.
2. Product → Archive → Organizer → Distribute App → App Store Connect →
   Upload. The Watch app and complication are embedded.
3. Export compliance: only standard HTTPS/Keychain/CloudKit encryption →
   exempt. Open item: set `ITSAppUsesNonExemptEncryption = NO` in the
   build settings so the question is not asked per build.

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
