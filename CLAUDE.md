# CLAUDE.md — Instructions for the coding agent

You are working on **Engelsystem Client**, a native SwiftUI client
(iOS, iPadOS, watchOS) for [Engelsystem](https://github.com/engelsystem/engelsystem/).
Read `README.md` and `docs/architecture.md` first. Deployment target:
iOS / watchOS 26.5.

## Language

Everything in the repository is **English**: code, comments, identifiers,
commit messages, documentation, UI strings. The owner may talk to you in
German; answer in German, write files in English.

## Work loop

1. Take the next open item from `docs/backlog.md` (top to bottom, unless
   told otherwise). Planning discussion goes to `docs/roadmap.md`.
2. Split it into small steps. Each step must leave the build green.
3. For each step: implement → write tests → update docs → verify → commit.
4. Remove the backlog item in the commit that completes it.
5. Stop and ask when a requirement is unclear or a decision is not
   covered by an ADR.

## Commit rules

- Commit **after every completed step**; do not batch unrelated changes.
- Conventional Commits with scope, e.g. `feat(kit): add MetricKitReporter`,
  `docs(adr): add template`. Scopes: `kit`, `ios`, `watch`, `complication`,
  `docs`, `adr`, `build`.
- Body: short rationale plus `Backlog: <ID>` when an item exists.
- Code, tests and affected docs in the same commit; update `CHANGELOG.md`
  for user-visible changes.
- **Push only when a larger block is finished or when asked**, never after
  every commit. Never force-push without explicit confirmation.

## Documentation map

Keep **all** of these current as work lands:

| File | Content |
|---|---|
| `README.md` | Human-facing overview, build/run, doc table |
| `CONTRIBUTING.md` | Workflow, commit rules, definition of done |
| `CHANGELOG.md` | User-visible changes (Keep a Changelog) |
| `docs/requirements.md` | Purpose, Phase 1 scope, Phase 2 rules, Watch scope |
| `docs/architecture.md` | Tech stack, structure, API, demo mode, sync, data flow |
| `docs/features.md` | Feature-by-feature current state; append as features land |
| `docs/testing.md` | Test practices and machine gotchas |
| `docs/security.md` | Credentials, transport, logging |
| `docs/app-store.md` | Identifiers, entitlements, privacy, export compliance |
| `docs/release.md` | TestFlight/App Store release checklist |
| `docs/privacy.md`, `docs/support.md` | Published legal pages — keep in sync with real data handling |
| `docs/guide.md`, `docs/faq.md` | Published user guide and FAQ (with images in `docs/assets/guide/`, refreshed by `Scripts/publish-guide-images.sh`) — keep in sync with user-visible behavior |
| `docs/history.md` | Closed investigations and lessons learned |
| `docs/roadmap.md` | Forward-looking planning and open decisions |
| `docs/backlog.md` | Ready-to-pick-up tasks (removed once done) |
| `docs/adr/` | Architecture Decision Records (index and template inside) |

`docs/_config.yml` lists which docs GitHub Pages must **not** publish —
update it with every added or renamed file in `docs/`.
Write an ADR for decisions with real trade-offs; routine choices belong in
`docs/features.md`.

## Quality gates

- **100 % line coverage is blocking** for every file not in
  `Scripts/coverage-exclusions.txt` (ADR 0009, 0010): no commit may leave the
  Kit, the iOS app or the Watch app below it. Run `Scripts/check-all-coverage.sh`
  (or `Scripts/check-coverage.sh` for the Kit alone) before committing.
  Exclusions: thin adapter layers over system APIs and pure SwiftUI layout files
  are standing-approved; anything else needs a justification comment **and**
  owner approval — never add one yourself.
- Always add tests for new features: Swift Testing (`import Testing`) in
  `EngelsystemClientKit`, XCUITest for non-trivial UI flows. Details:
  `docs/testing.md`.
- Verify with a full Xcode build of the iOS **and** Watch app, not only
  `swift test` (macOS compiles platform-guarded code out).
- No force unwraps in new code without a reason.

## Architecture rules

- Shared logic lives in `EngelsystemClientKit`; views and view models in
  the app targets. `@Observable` view models, `NavigationSplitView` on iPad.
- DTOs are generated from `openapi.yml` — never hand-edit `Generated/`.
- Demo data lives only in `APIClient`/`DemoData`, never in views.
- Notifications are local only; never assume server-side push.
- Sync is iCloud-based; WatchConnectivity is only an optional nudge.
- Phase 2 features (shift sign-up, create/edit shifts) are not built, and
  not prepared as disabled/hidden UI, until the backend endpoint exists.

## Security

- Credentials only in the Keychain. Never log API keys or tokens.
- No trust exceptions for invalid TLS certificates. See `docs/security.md`.

## Dependencies

- No new third-party dependency without an ADR. The project is GPL-2.0;
  dependency licenses must be compatible.

## Useful commands

```sh
cd EngelsystemClientKit && swift test               # Kit unit tests (macOS)
xcodebuild build -scheme EngelsystemClient -destination 'generic/platform=iOS Simulator'
xcodebuild test -scheme EngelsystemClient -destination 'platform=iOS Simulator,name=<device>' -parallel-testing-enabled NO
Scripts/check-all-coverage.sh                        # all three 100 % coverage gates (Kit, iOS app, Watch app)
Scripts/check-coverage.sh                            # Kit tests + coverage gate only (fast)
Scripts/generate-api.sh                              # regenerate DTOs from openapi.yml
```
