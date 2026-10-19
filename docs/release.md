# Release checklist (TestFlight / App Store)

Run top to bottom for every build. Identifiers and metadata:
[`app-store.md`](app-store.md); policy pages: [`privacy.md`](privacy.md),
[`support.md`](support.md).

## Decide before the first App Store release

- **Debug logging default**: it is **on** by default in the beta (`DebugLog.defaultEnabled`, `docs/privacy.md`). Decide again before the first
  App Store release — probably **off** — and then change the one constant and the sentence in the privacy policy together.

## Before archiving

1. Working tree clean, `main` up to date.
2. `swift test` in `EngelsystemClientKit` green, plus a full Xcode build of
   the iOS app **and** the Watch app (`xcodebuild build -scheme …`) and the
   app test targets.
3. The build number is the commit count and needs no bump (see "Build number" in [`app-store.md`](app-store.md));
   bump `MARKETING_VERSION` for a new release (in the Xcode project). Commit first — the same commit cannot be
   uploaded twice.
4. **CloudKit schema:** if a SwiftData model changed (new model, new or changed field), open the CloudKit Dashboard,
   container `iCloud.net.cuccato.engelsystem.de`, and *Deploy Schema Changes* from Development to Production **before**
   the build reaches testers. TestFlight and App Store builds use the Production environment; without the deployed
   schema the sync of instances fails silently (history: 2026-10-19).
5. Check [`privacy.md`](privacy.md) still matches the shipped data handling.
6. **Changelog:** in the commit that bumps the version, rename `## [Unreleased]` in
   [`CHANGELOG.md`](../CHANGELOG.md) to `## [<MARKETING_VERSION>] - <date>` (the build number is `git rev-list --count v<version>`, so it is not written down),
   add a fresh empty `## [Unreleased]` above it and update the compare links at the bottom.

## Archive and upload

The signed-in Apple account lives in Xcode's GUI session: `xcodebuild -exportArchive`
from a terminal fails with "No Accounts", so **distribute from the Xcode Organizer**
(Window → Organizer → Archives → Distribute App → App Store Connect → Upload). A CLI
archive is fine for validating that the project builds and embeds the Watch app and
complication.

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

- **Tag** the exact commit the uploaded archive was built from (not a later docs commit) with an
  annotated tag `v<MARKETING_VERSION>`. The tag message **contains the changelog section** of that
  version, so GitHub shows real content on the tag page. Extract it from `CHANGELOG.md` instead of
  typing a one-liner:
  `{ echo "Version 0.1.0 (build 2)"; echo; awk '/^## \[0.1.0\]/{f=1;next} /^## \[/{f=0} f' CHANGELOG.md; } > /tmp/tag-msg && git tag -a v0.1.0 <commit> -F /tmp/tag-msg`
  (use the scratchpad instead of `/tmp` in agent sessions; check with `git show v0.1.0`).
- **GitHub Release:** after pushing the tag, create a Release from it so the notes show under
  "Releases": `gh release create v0.1.0 --title "Version 0.1.0" --notes-file <changelog section>`
  (the same text as the tag message, without its first line).
  Every upload that ships to testers or the store gets a tag; a further build of the same marketing
  version uses `v<MARKETING_VERSION>-<build>` (e.g. `v0.1.0-3`). Push tags together with the next
  block of commits (or when asked): `git push origin <tag>`.
- Make sure the changelog entry for that version exists (step 5 above) **before** archiving, so the
  tagged commit already contains it.
- Move the finished entries from [`roadmap.md`](roadmap.md)/[`backlog.md`](backlog.md) into
  [`features.md`](features.md).

## Draft texts for TestFlight Test Information

- **Beta App Description**: "Engelsystem Client is an unofficial companion app for the
  Engelsystem volunteer-management system used by events like the Chaos Communication
  Congress. See your own shifts, news, locations and messages, get local reminders before a
  shift, and glance at your next shift on Apple Watch. Please test: adding your instance's
  server with an API key, shift reminders, the Watch app and complication, and pull-to-refresh.
  No server? Tap 'Try Demo Mode' on the first screen."
- **What to Test** (per build), version 0.2.0: "Please test: (1) the new shift detail page (tap a shift) and the Filter menu of
  Shifts and News; (2) several instances at once — colors, the colored bands and instance tags, display modes in
  Settings > Instances, 'Parallel Syncs' and the sync banner with Stop/Skip; (3) one page per instance (name, server, API key, Save/
  Discard) and its Features list — areas your server or account does not offer are hidden quietly; (4) tappable phone numbers
  (Settings > Phone Numbers); (5) the map inside a location (Settings > Privacy); (6) Apple Watch: Settings pages, the larger
  switch in Instances, and Diagnostics > Send Log to iPhone with the iPhone's Diagnostics > Logs received from Apple Watch.
  The app also runs on Macs with Apple silicon — feedback welcome. Debug logging is on in the beta; please attach Settings >
  Diagnostics > Export Diagnostics to bug reports (nothing is sent automatically). Demo Mode: 'Try Demo Mode' on the first screen."
  *(0.1.0 was: "First TestFlight build: setup and Demo Mode, Shifts/News/Profile/Locations/Messages, reminders, Watch app and complication,
  Settings (including Export Diagnostics).")*
- **Beta App Review notes**: "No account is needed. On the first screen tap 'Try Demo Mode' — it
  uses built-in sample data and sends no API requests (the demo location “Workshop Room A” links to the project's GitHub page as its map). A real Engelsystem instance and API key
  are only needed to test against an actual server."
- **Feedback Email**: `EngelsystemClient@cuccato.net`; **Privacy Policy URL**:
  `https://cookieberlin.github.io/EngelsystemClient/privacy`; **Support**:
  `https://cookieberlin.github.io/EngelsystemClient/support`.
