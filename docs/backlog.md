# Backlog

Concrete, ready-to-pick-up development tasks (IDs like `T-01`; reference them as
`Backlog: T-01` in commit bodies) — the tactical counterpart
to [`roadmap.md`](roadmap.md)'s strategic/feature-level planning. An
item moves here once it's broken down enough that someone could
actually start on it; it's removed (not just checked off) once it's
done and reflected in [`features.md`](features.md).

## TestFlight release

- [ ] **T-01** Upload a first build (Xcode Archive → App Store Connect); see
      `release.md`. Export compliance is pre-answered in the Info.plist.
- [ ] **T-02** Set up Internal Testing group and upload a build.
- [ ] **T-03** Prepare for External Testing / Beta App Review (Beta App
      Description, Feedback Email, demo-mode hint for reviewers) once
      Internal Testing is confirmed working.

## Coverage follow-ups (ADR 0009/0010)

The ramp-up is finished: all three gates pass (2026-10-12). Open follow-ups:

- [ ] **C-08** XCUITest smoke tests for screens that have none yet (Messages,
      Locations, Settings > Export Diagnostics), so the excluded views are at
      least proven to render and navigate.
- [ ] **C-09** Code behind `#if os(iOS)` in the Kit (the MetricKit delivery callbacks,
      `WatchConnectivityBridge`'s iOS branches) is not compiled by `swift test` on
      macOS; measure it through an Xcode coverage run or propose an exclusion.
- [ ] **C-10** `EngelsystemClientTests/StubbedNetwork.swift` is a copy of the Kit's
      test helper (and the Watch tests use an offline URL instead); consider a
      shared test-support package.
