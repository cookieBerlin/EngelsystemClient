# Roadmap

Forward-looking planning: features not yet implemented, release
planning, and open decisions awaiting the user's input. Move an item
here as soon as planning firms up past "just an idea" — not just in
chat. Once a planned item is broken into concrete tasks, move those
into [`backlog.md`](backlog.md); once it actually ships, move its entry
into [`features.md`](features.md) with a dated
note and remove it from here.

## In progress

### TestFlight release (started 2026-10-09)

Goal: get the app into TestFlight, both Internal and External testing.

- **Repo visibility**: the GitHub repo (`cookieBerlin/EngelsystemClient`)
  is currently private and will be switched to public by the user
  themselves (not by Claude) before Pages can serve it on the free plan.
- **Security/privacy audit of the full repo + git history**, done
  2026-10-09 ahead of going public — see
  [`history.md`](history.md#2026-10-09-pre-public-security-audit) for
  the full writeup. Result: no real secrets/credentials ever committed.
  Two low-risk informational items found; both resolved the same day —
  the private LAN IP in `CLAUDE.md` was redacted immediately, and the
  old local absolute path in git history was scrubbed via a full
  `git filter-repo --replace-text` rewrite (user-approved — see "Open
  decisions" below for the now-resolved record).
- **LICENSE added 2026-10-09**: GPL-2.0 (user's explicit choice — not
  MIT/Apache-2.0, the two more common defaults for a project like this,
  so noted here rather than assumed). Inserted at the very first commit
  (via `git rebase --root`, same rewrite pass as the history scrub
  above) so the whole project's history is covered by it, not just
  commits from 2026-10-09 onward.
- **Required Apple-facing web pages, hosted via GitHub Pages** (chosen
  over a GitHub Wiki — see [`adr/`](adr/) once that decision gets its
  own ADR, or treat this roadmap entry as the record for now):
  - Privacy Policy — required by App Store Connect before any
    TestFlight build (internal or external) can be distributed.
    Content generated from the app's actual data handling (CloudKit
    sync, Keychain storage, local-only notifications, no analytics/
    tracking, Demo Mode, and — since 2026-10-09 — on-device MetricKit
    crash/diagnostics reporting, see `features.md`'s
    `MetricKitReporter` entry) — not boilerplate. **Must be kept up to
    date whenever data handling changes** — same standing-maintenance
    expectation as `CLAUDE.md` itself.
  - Support page — contact method: GitHub Issues **and**
    `EngelsystemClient@cuccato.net`.
  - Both served from `docs/` on `main` via GitHub Pages (Jekyll
    auto-renders Markdown — no separate build step), default
    `<user>.github.io/<repo>/...` URL, no custom domain.
  - **Content written 2026-10-09**: `docs/privacy.md`, `docs/support.md`,
    `docs/index.md`, and `docs/_config.yml` (theme `jekyll-theme-minimal`,
    excludes the dev-facing docs — `architecture.md`/
    `features.md`/`app-store.md`/`history.md`/
    `roadmap.md`/`backlog.md`/`adr/` — from being published as public
    pages, so CLAUDE.md's existing cross-references into `docs/*.md`
    keep working unchanged). Not yet verified live — needs the repo to
    actually go public and GitHub Pages enabled first (see
    `backlog.md`).
- **Repo public, Pages live, app record created** (2026-10-12): Privacy/
  Support URLs verified (HTTP 200) at `cookieberlin.github.io/EngelsystemClient/`.
  Git history was re-scrubbed and force-pushed first (private LAN IP removed).
- **App Store Connect metadata** — app record exists; still open: Beta
  App Description, Feedback Email, export compliance questions.
- **Internal Testing group** — done 2026-10-12 (build 0.1.0 (2)).
- **External Testing** — submitted for Beta App Review 2026-10-12 (build 0.1.0 (2)); waiting
  for Apple.

### App Store screenshots, generated automatically (planned 2026-10-12)

Goal: one command produces every screenshot the App Store needs, reproducibly, from Demo Mode.
Decisions (owner, 2026-10-12): devices **iPhone 6.9", iPad 13", Apple Watch**; scenes **Shifts, News,
Profile, Locations, Messages (a conversation), Settings**; **light appearance only**; **plain
screenshots** (no frames/captions); English only.

Design:

- **Entry point** `Scripts/screenshots.sh [iphone|ipad|watch|all]`, native tooling only
  (`xcodebuild`, `simctl`, `xcresulttool`, `sips`) — no fastlane/Ruby dependency (would need an ADR
  and adds nothing here). Output `Screenshots/<device>/en/NN-<scene>.png`, git-ignored.
- **Own simulators** created on demand by the script ("EngelsystemClient Screenshots iPhone/iPad/
  Watch": iPhone 18 Pro Max, iPad Pro 13-inch M5, Apple Watch Ultra 4), so the developer's simulators
  stay untouched. Prepared per run: English (US), light appearance, status bar override
  (9:41, full battery/Wi-Fi/cellular), freshly erased app state.
- **iPhone/iPad scenes** are a new XCUITest class `ScreenshotTests` in `EngelsystemClientUITests`
  (run via `-only-testing:EngelsystemClientUITests/ScreenshotTests`, no extra test plan; it takes minutes, so it is not part of the normal runs): launch → "Try Demo Mode" → sidebar →
  open each screen → `capture("01-shifts")` as a kept `XCTAttachment`. iPad runs in landscape. The script
  exports the attachments from the `.xcresult` and renames them in scene order.
- **Watch**: UI tests on the Watch simulator are slow and flaky (see `history.md`), so the Watch scene
  uses a **DEBUG-only launch argument** (`-seed-demo-instance`) that inserts a demo instance on launch;
  the script launches the Watch app with it and grabs `simctl io … screenshot`. Same argument available
  to the iOS scenes to skip the setup screen where that makes a scene faster. The decision logic
  (`shouldSeedDemoInstance(arguments:)`) lives in a tested type; the seeding adapter is thin.
- **Verification step** in the script: each PNG must have the exact pixel size the App Store accepts for
  its device class (table kept in the script, checked against App Store Connect's screenshot
  specifications when implemented); EXIF/XMP stripped from the PNGs; the run fails if a scene is missing.
- **Docs**: new "Screenshots" section in `app-store.md` (devices, sizes, scenes, how to add a scene),
  step added to `release.md`, `.gitignore` entry, ADR for "native tooling, DEBUG seed argument".
- **Coverage gate**: new app-side code stays at 100 % (seed decision tested; adapter excluded as a thin
  adapter); UI test code is not measured.
- **Constraints**: needs an unlocked screen (UI tests), about 10–15 minutes for all devices, and must not
  use the developer's own simulators.

Steps (each its own commit): 1 `-seed-demo-instance` + tests; 2 `ScreenshotTests` for iPhone with
`capture` helper + test plan; 3 `Scripts/screenshots.sh` for iPhone (simulator prep, export, rename,
size check); 4 iPad (landscape); 5 Watch; 6 docs + ADR; 7 full run and review of every image.

## Open decisions

Awaiting the user's input — nothing below should be assumed/acted on
until answered. _(none currently open)_

## Resolved decisions

Kept for the record, now that these are no longer blocking anything:

1. **Old local absolute path in git history** (an early commit of
   `Scripts/generate-api.sh` hardcoded `/Users/cookie/Documents/
   Projekte/...`, fixed in the current script, which resolves its own
   path at runtime): **rewrite it** — done 2026-10-09 via
   `git filter-repo --replace-text`, combined with the LICENSE-insertion
   rewrite below in one pass. All 83 commit hashes changed again (same
   scope as the 2026-09 German-content rewrite); verified 0 remaining
   occurrences of the real path across all history afterward, and that
   `EngelsystemClientKit` still builds clean post-rewrite.
2. **MetricKit data handling model**: **local + manual export/share** —
   implemented 2026-10-09 as `MetricKitReporter`, see
   `features.md` for the full writeup.
3. **LICENSE**: **GPL-2.0** — added 2026-10-09, the canonical text
   fetched verbatim from `gnu.org` (not reconstructed from memory, to
   avoid any inaccuracy in a legal document) and inserted into the very
   first commit via `git rebase --root`, so it covers the project's
   entire history, not just new commits.
