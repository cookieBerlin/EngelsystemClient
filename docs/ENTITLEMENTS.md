# Entitlements & Signing

Part of the Engelsystem Client documentation set — see [`CLAUDE.md`](../CLAUDE.md) for the entry point and the rest of the doc map. For the story of how this configuration was arrived at (bundle-ID collisions, namespace churn, App ID quota, etc.), see [`history.md`](history.md).

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
  **Scheme pre-actions/post-actions only run when archiving through
  Xcode's own UI (Product → Archive) — `xcodebuild archive` from the
  command line does not execute them at all.** This project's testing
  this session has been almost entirely `xcodebuild` CLI, so this
  specific behavior could not be (and was not) verified end-to-end the
  same way as everything else — verify manually via Xcode's Organizer
  the first time this matters for a real archive. `agvtool` also prints
  `Cannot find "NO"`/`Cannot find "YES"` noise while doing this (it
  appears to misinterpret some unrelated `GENERATE_INFOPLIST_FILE`
  build-setting values elsewhere in the project as candidate Info.plist
  paths) — harmless, the actual version bump still lands correctly
  despite the noise.
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

