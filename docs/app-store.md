# App Store: identifiers, entitlements, privacy

Part of the Engelsystem Client documentation set — see [`CLAUDE.md`](../CLAUDE.md) for the entry point and the rest of the doc map. For the story of how this configuration was arrived at (bundle-ID collisions, namespace churn, App ID quota, etc.), see [`history.md`](history.md).

## Identifiers

| Target | Bundle ID |
|---|---|
| iOS/iPadOS app | `net.cuccato.engelsystem.de.EngelsystemClient` |
| Watch app | `net.cuccato.engelsystem.de.EngelsystemClient.watchkitapp` |
| Complication extension | `net.cuccato.engelsystem.de.EngelsystemClient.watchkitapp.nextshiftcomplication` |

Team ID `8A5FNU94BM` (not secret). Version `0.1.0` (build `1`) in
`project.pbxproj` (`MARKETING_VERSION`/`CURRENT_PROJECT_VERSION`).
The history of the namespace changes is in [`history.md`](history.md).

## Privacy and legal pages

- Privacy Policy: [`privacy.md`](privacy.md), Support: [`support.md`](support.md),
  published via GitHub Pages at
  `https://cookieberlin.github.io/EngelsystemClient/` (see
  [ADR 0001](adr/0001-github-pages-over-wiki-for-legal-pages.md)).
- **Keep `privacy.md` in sync with the real data handling** whenever
  storage, networking, analytics or diagnostics change.
- Contact for both: GitHub Issues and `EngelsystemClient@cuccato.net`.
- License: GPL-2.0 (`LICENSE`).

## Export compliance (encryption)

The app only uses Apple's standard encryption (HTTPS via `URLSession`,
Keychain, CloudKit) — no proprietary or non-standard cryptography. That
normally qualifies for the exemption. `ITSAppUsesNonExemptEncryption =
NO` is therefore set in `EngelsystemClient-Info.plist` (2026-10-12), so App
Store Connect does not ask the export-compliance question for every
build. Revisit this if the app ever adds its own cryptography.

## Current configuration (both targets: iOS app + Watch app)

- iCloud → CloudKit, same container: `iCloud.net.cuccato.engelsystem.de`
- Keychain Sharing, same access group:
  `$(AppIdentifierPrefix)net.cuccato.engelsystem.de.shared`
- **Background Modes, both targets: `remote-notification` only** — required
  for CloudKit's silent-push-triggered sync (SwiftData's CloudKit mirroring
  needs this to receive remote-change notifications in the background;
  without it, CloudKit itself raises a hard runtime error, `"BUG IN CLIENT
  OF CLOUDKIT: CloudKit push notifications require the 'remote-notification'
  background mode in your info plist"`, the first time it tries to register).
  This entry previously (incorrectly) said "Background fetch, Background
  processing" — those were **never actually implemented**: no
  `BGTaskScheduler`/`BGAppRefreshTask`/`BGProcessingTask` code exists
  anywhere in this codebase, so that line was aspirational documentation
  that had drifted from reality, not a real capability. Corrected
  2026-09-17 when the CloudKit runtime error above surfaced during Simulator
  sync testing and this project.pbxproj gap was found (`grep
  UIBackgroundModes project.pbxproj` returned nothing at all beforehand).
- **No** push-notification entitlement needed (local notifications only) —
  the CloudKit-driven silent push above is handled entirely by the system/
  CloudKit framework via the Background Mode capability, not by this app
  requesting `UNAuthorizationOptions` push permission or handling APNs
  device tokens itself.

**`INFOPLIST_KEY_UIBackgroundModes`/`INFOPLIST_KEY_WKBackgroundModes` do
not work as build settings on this Xcode version — a real Info.plist
fragment file is required instead.** Both targets use
`GENERATE_INFOPLIST_FILE = YES` (no checked-in Info.plist), and most
Info.plist keys *are* successfully synthesized this way from
`INFOPLIST_KEY_<Key>` build settings (confirmed working:
`UISupportedInterfaceOrientations`, `UIApplicationSceneManifest`,
`WKCompanionAppBundleIdentifier`, etc.) — but `UIBackgroundModes`
specifically is not on whatever internal list of keys Xcode's
Info.plist-generation step recognizes for this synthesis: setting
`INFOPLIST_KEY_UIBackgroundModes` (tried both as a plain string and as a
proper pbxproj array) resolved correctly per `xcodebuild
-showBuildSettings`, but never appeared in the built `Info.plist` no
matter how many times the build was cleaned — confirmed by inspecting
the built bundle directly with `plutil -p`, not just trusting a
successful build. **Fix**: add back a real, minimal Info.plist file
containing just the one key, and reference it via `INFOPLIST_FILE`
*alongside* keeping `GENERATE_INFOPLIST_FILE = YES` — Xcode merges the
two (confirmed: every other synthesized key was still present in the
built plist afterward). The fragment files
(`EngelsystemClient-Info.plist`, `EngelsystemClientWatchApp-Info.plist`)
live at the **project root**, sibling to `EngelsystemClient.xcodeproj`,
**not** inside either target's own folder — both `EngelsystemClient/`
and `EngelsystemClient Watch App/` are
`PBXFileSystemSynchronizedRootGroup`s (see "Project/target structure" in
[`CLAUDE.md`](../CLAUDE.md)), so a loose file dropped inside one gets automatically added to
that target's "Copy Bundle Resources" build phase, which then collides
with the same file also being used as `INFOPLIST_FILE` (`"duplicate
output file ... Info.plist"` — hit this exact error before moving the
files out). If you ever need to add another Info.plist key that doesn't
synthesize via `INFOPLIST_KEY_*`, add it to these existing fragment
files rather than creating new ones.

> **Watch out going forward**: bundle identifiers are unique across *all* Apple developer accounts, not just this project or team — a rename can fail on a real device with "cannot be registered ... because it is not available" if some other account already holds that exact string (Simulator builds never surface this). And a free/personal Apple Developer account can only register **10 new App IDs per rolling 7-day window** — renaming several targets' bundle identifiers in quick succession can burn through that quota. Both were hit for real during this project's setup; see [`history.md`](history.md) for the details. Treat `net.cuccato.engelsystem.de.*` as settled and avoid further bundle-identifier churn unless there's a strong reason.

**`GitCommitHash` Info.plist key + build-number-on-archive (2026-09-17),
both added via the `xcodeproj` Ruby gem, not by hand-editing
`project.pbxproj`/`.xcscheme` directly** (same tool already used for
`EngelsystemComplication` — see "Complication" in
[`features.md`](features.md)):
- **Every build** (`EngelsystemClient`, `EngelsystemClient Watch App Watch
  App`, both Debug and Release) runs a `PBXShellScriptBuildPhase` named
  "Embed Git Commit Hash" — the last build phase, after Copy Bundle
  Resources — that shells out to `git rev-parse --short HEAD` and writes
  the result into a `GitCommitHash` key in the already-built
  `Info.plist` via `PlistBuddy`, so any build (including a plain
  Simulator debug run) can be traced back to the exact commit it came
  from. It's marked `always_out_of_date` so the new build system runs it
  on every build rather than caching it as "up to date".
  - **This required disabling `ENABLE_USER_SCRIPT_SANDBOXING` for both
    targets** (`= NO`, overriding the project-level `= YES` default).
    Xcode 15+'s Run Script sandboxing silently blocks a script's writes
    to any file not declared in its `outputPaths` — the write appeared
    to succeed (exit code 0, no logged error) but the built `Info.plist`
    never actually changed. Declaring the real `Info.plist` path as this
    phase's `outputPaths` (the obvious fix) doesn't work either: it then
    collides with Xcode's own `ProcessInfoPlistFile` task, which also
    claims that path as its output (`"duplicate output file"` build
    error) — confirmed both failure modes hands-on before landing on
    disabling sandboxing for these two targets as the practical fix.
- **Build number (`CURRENT_PROJECT_VERSION`/`CFBundleVersion`) only
  auto-increments when archiving**, not on every build — deliberately
  *not* done via a per-target Run Script Build Phase gated on
  `${ACTION}`, because the iOS app target depends on (and builds after)
  the Watch app target, so a phase living on the iOS target would bump
  the version too late for the already-built Watch app's own Info.plist.
  Instead: `VERSIONING_SYSTEM = apple-generic` on both targets (enables
  `agvtool`), plus an **Archive-action pre-action** on the
  `EngelsystemClient.xcscheme` scheme (`<PreActions>` under
  `<ArchiveAction>`) running `xcrun agvtool next-version -all`, which
  runs once, before *any* target starts building, and bumps
  `CURRENT_PROJECT_VERSION` across every target in the project
  consistently (confirmed hands-on: 1 → 2 across all 14 build configs in
  one invocation, iOS + Watch + both test targets + Complication).
  **Verified 2026-10-12 (first real archive): `xcodebuild archive` from the command
  line *does* run the pre-action too**, but the bump then lands *during* the build —
  the app target had already read build number 1 while the complication's
  `Info.plist` picked up the freshly written literal `2`, so the archive was
  inconsistent (app 1 / complication 2) and would fail App Store validation. For a
  CLI archive pass the number explicitly (`xcodebuild archive … CURRENT_PROJECT_VERSION=<n>`
  where `<n>` is the current number + 1) so every bundle agrees, then commit the bumped
  `project.pbxproj`/`EngelsystemComplication/Info.plist`. In Xcode's UI (Product →
  Archive) the pre-action runs before the build and is consistent. `agvtool` also prints
  `Cannot find "NO"`/`Cannot find "YES"` noise while doing this — harmless.
- **App Group** `group.net.cuccato.engelsystem.de.shared` (Watch app + `EngelsystemComplication`
  extension only, not iOS): shares the next-shift snapshot with the complication
  process (see "Watch app scope" in [`CLAUDE.md`](../CLAUDE.md) and "Complication" in
  [`features.md`](features.md)). Confirmed working
  for local simulator builds with the free/personal team already configured in
  this project (`DEVELOPMENT_TEAM = 8A5FNU94BM` — changed from the original
  `TYG73A374P` after the user switched the Apple ID signed in to Xcode for
  this project; Xcode's automatic signing picked up the new team ID on the
  next build) — **unlike CloudKit containers,
  App Groups and Keychain Sharing don't require a paid Apple Developer Program
  membership**, only automatic signing with any team.

## Screenshots

`Scripts/screenshots.sh [iphone|ipad|watch|all]` generates every App Store screenshot from Demo Mode into
`Screenshots/<device>/en/NN-<scene>.png` (git-ignored); design and rationale in
[ADR 0011](adr/0011-native-tooling-for-app-store-screenshots.md). It creates and uses its own simulators, sets English (US),
light appearance and the 9:41 status bar, runs the scenes on a fresh install, verifies the exact pixel size and fails if a
scene is missing. Needs an unlocked screen; a run takes several minutes per device.

| Device | Simulator (created by the script) | Size | Scenes |
|---|---|---|---|
| iPhone | iPhone 18 Pro Max | 1320 × 2868 | `01-shifts`, `02-news`, `03-profile`, `04-locations`, `05-messages`, `06-settings` |
| iPad | iPad Pro 13-inch (M5), landscape | 2752 × 2064 | the same six |
| Apple Watch | Apple Watch Ultra 4 (49mm) | 422 × 514 | `01-next-shift`, `02-settings` |

Sizes checked against App Store Connect's "Screenshot specifications" on 2026-10-12.

- **Add or change an iPhone/iPad scene**: edit `EngelsystemClientUITests/ScreenshotTests.swift` (a `capture("NN-name")` call after
  opening the screen) and add the name to `SCENES` in the script. Scene content comes from `DemoData`.
- **Watch**: no UI test; the Debug build is launched with `-seed-demo-instance -skipNotificationPrompt YES` and captured with
  `simctl io screenshot`. Both launch arguments do nothing in Release builds.
- **Guide images**: `Scripts/publish-guide-images.sh` copies small versions of these screenshots into `docs/assets/guide/` for the
  published [user guide](guide.md); rerun it (after `Scripts/screenshots.sh`) whenever the UI or the demo data changes visibly and
  commit the result.
- **Known cosmetics**: the Watch shows the real time; the iPad shows its windowing chrome (app name in the status bar, a
  window handle in the lower right corner); some screens show "Last Synced: …".
- **Gotchas**: build with normal simulator signing (never `CODE_SIGNING_ALLOWED=NO`); the first sync's notification prompt only
  appears after a real interaction, so the test keeps nudging it; Apple's `WidgetRenderer_Default` may log a watchdog crash
  report on a fresh simulator — harmless.
