# Project: Engelsystem Client (iOS/iPadOS/watchOS)

This document is the binding core of the project's architecture and
constraints. Read it in full before generating code or making
suggestions.

## Documentation map

This documentation is split across several files, split out
2026-09-23 once this file alone had grown past 2500 lines. Keep **all**
of them up to date as work lands — not just this file:

- **`CLAUDE.md`** (this file) — purpose, scope, API summary, tech
  stack, project/target structure, Watch app scope, implementation
  status, testing practices, and hard constraints. The compact core
  every session needs.
- **[`README.md`](README.md)** — short, human-facing overview for
  GitHub visitors (what this is, how to build/run it). Update it
  whenever the project's purpose, scope, or build/run steps change.
- **[`docs/architecture.md`](docs/architecture.md)** — the current
  design: multi-instance concept, iOS↔Watch sync strategy, background
  sync, the data/code flow and its error-handling rules, and CloudKit
  sync for `Instance` metadata.
- **[`docs/features.md`](docs/features.md)** —
  feature-by-feature current state of `EngelsystemClientKit`, the iOS
  app, and the watchOS app. The single biggest, fastest-growing
  document — append here as features land.
- **[`docs/app-store.md`](docs/app-store.md)** — current
  entitlements/signing configuration and actionable Xcode/Info.plist
  gotchas.
- **[`docs/history.md`](docs/history.md)** — investigations, bugs, and
  decisions that are no longer needed to understand today's code, kept
  for the lessons learned. Add here rather than letting closed
  investigations bloat the current-state docs above.
- **[`docs/roadmap.md`](docs/roadmap.md)** — forward-looking planning:
  not-yet-implemented features, release planning (e.g. TestFlight), and
  open decisions awaiting the user's input. All planning discussion
  belongs here, not just in chat — move it here as soon as it firms up
  past "just an idea," and move an item out (into
  `docs/features.md`, with a dated note) once it actually
  ships.
- **[`docs/adr/`](docs/adr/)** — Architecture Decision Records, one file
  per significant architectural decision going forward (started
  2026-10-09; existing decisions made before this date live in their
  original narrative form in `docs/architecture.md`/`docs/history.md`
  and are **not** being retroactively converted, unless asked). See
  [`docs/adr/README.md`](docs/adr/README.md) for the index and template.
  Write a new ADR whenever a decision has real trade-offs worth
  recording for a future session — not for routine implementation
  choices that `docs/features.md` already captures fine.
- **[`docs/backlog.md`](docs/backlog.md)** — concrete, ready-to-pick-up
  development tasks for the next work sessions — the tactical
  counterpart to `docs/roadmap.md`'s strategic/feature-level planning.
  A Roadmap item moves to the Backlog once it's broken down into actual
  tasks someone could start on; a Backlog item is removed (not just
  checked off) once it's done and reflected in
  `docs/features.md`.

## Scope and requirements

Moved to [`docs/requirements.md`](docs/requirements.md) (D-04, 2026-10-12): purpose,
Phase 1 scope, **Phase 2 (do not implement now; no disabled/hidden UI
for backend features that do not exist yet)**, Watch app scope (deliberately
minimal, except Settings parity) and the implementation order.

## API, demo mode, tech stack, project structure

Moved to [`docs/architecture.md`](docs/architecture.md) (D-03, 2026-10-12):

- **Tech stack (binding)** — SwiftUI/`@Observable`, SwiftData + CloudKit,
  generated DTOs (never hand-written), `URLSession` + async/await,
  Keychain, local-only notifications.
- **Project/target structure** and the Watch app target rename note.
- **API** — OpenAPI source, auth, endpoint list and the provenance of
  not-yet-merged server branches (`/news/{id}`, `/locations/{id}`,
  `/messages`).
- **Demo mode** — sentinel-URL approach in `APIClient`/`DemoData`.

## Testing

Binding rules (details, commands and machine-specific gotchas in
[`docs/testing.md`](docs/testing.md)):

- **Always add tests for new features** — logic in `EngelsystemClientKit`
  gets Swift Testing unit tests (`swift test` from `EngelsystemClientKit`),
  non-trivial UI flows get an XCUITest. No XCTest for unit tests.
- Verify with a full Xcode build, not only `swift test` (macOS compiles
  platform-guarded code out).
- `xcodebuild test` on iOS: add `-parallel-testing-enabled NO`.

## Important constraints that apply to every implementation step

- No disabled/hidden buttons for backend features that don't exist yet
  (Phase 2)
- Push notifications exclusively local, never assume server-side push
- Do not hand-modify OpenAPI codegen output — changes belong in
  `openapi.yml` or in a mapping layer outside of `Generated/`
- Sync mechanism is iCloud-based, not WatchConnectivity-based
