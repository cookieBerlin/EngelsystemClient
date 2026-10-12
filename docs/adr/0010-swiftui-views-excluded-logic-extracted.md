# 0010. SwiftUI view bodies are excluded from the coverage gate; their logic is extracted and tested

- **Status**: Accepted
- **Date**: 2026-10-12

## Context

[ADR 0009](0009-full-line-coverage-gate.md) applies the 100 % line coverage gate
to the whole project. Measured 2026-10-12, the iOS app target had 5204 of
6161 lines uncovered by unit tests, about 4500 of them in SwiftUI view files
(`SettingsView` alone is 1154 lines). Covering every `body` hierarchy and
every conditional branch through XCUITest would be slow and fragile (error
banners, 401 redirects and similar need stub servers), and view-inspection
libraries would add a third-party dependency without covering every branch.

## Decision

- Decisions and calculations that live in a view move into view models or
  static helper functions (as already done for `MainView.initialSelection`
  etc.) and are covered to 100 % by unit tests.
- Files that are pure SwiftUI layout (a `body` hierarchy plus bindings, no
  logic worth testing separately) are listed in `Scripts/coverage-exclusions.txt`
  with a justification and owner approval (granted for this approach on
  2026-10-12), and are protected by XCUITest smoke tests that prove they
  render and navigate.
- Non-view files in the app target (view models, services, helpers) are
  **not** excluded and must reach 100 %.
- `Scripts/check-app-coverage.sh` checks the app target from an Xcode
  coverage run.

## Consequences

- The gate stays meaningful for logic without demanding pixel-level tests.
- A layout file that grows real logic must lose its exclusion: extract the
  logic and test it.
- Some refactoring of the large views (notably `SettingsView`, `MainView`)
  is needed before they can be excluded honestly.
