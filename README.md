# Engelsystem Client

A native Apple client for [Engelsystem](https://github.com/engelsystem/engelsystem/),
the volunteer-management system used by events like the Chaos Communication
Congress. It talks to the official REST API of your Engelsystem instance —
no server-side changes required.

**Website:** <https://cookieberlin.github.io/EngelsystemClient/> — the
[user guide](https://cookieberlin.github.io/EngelsystemClient/guide), the
[FAQ](https://cookieberlin.github.io/EngelsystemClient/faq),
[support](https://cookieberlin.github.io/EngelsystemClient/support) and the
[privacy policy](https://cookieberlin.github.io/EngelsystemClient/privacy), plus the link to join the beta on TestFlight.

## Features

- View your own shifts, grouped by day
- Read news/announcements, including comments
- View your profile, angel types, and worklogs
- Browse locations/rooms, linked from each shift
- Send and receive private messages (on instances whose server supports it)
- Local reminders before your shifts start (no server push involved)
- Manage multiple Engelsystem instances/instances at once
- A companion Apple Watch app showing just your next shift, plus a
  complication
- A demo mode to try the app without a real server or API key

## Requirements

- Xcode 27 or newer
- iOS/iPadOS 26.5+, watchOS 26.5+

## Building

Open `EngelsystemClient.xcodeproj` in Xcode and run the `EngelsystemClient`
scheme (or `EngelsystemClient Watch App` for the Watch app). No external
package manager step is needed beyond Xcode resolving the local
`EngelsystemClientKit` Swift package.

To try it without a real server, use "Try Demo Mode" on the first screen.

## Testing

```sh
# Unit tests for the shared package (no simulator needed)
cd EngelsystemClientKit && swift test

# UI tests (adjust the destination to a simulator on your machine)
xcodebuild test -scheme EngelsystemClient \
  -destination 'platform=iOS Simulator,name=<device>' \
  -only-testing:EngelsystemClientUITests
```

## Documentation

| Document | Content |
|----------|---------|
| [CLAUDE.md](CLAUDE.md) | Rules for the coding agent, documentation map |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Workflow, commit rules, definition of done |
| [SECURITY.md](SECURITY.md), [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) | Reporting vulnerabilities, community rules |
| [CHANGELOG.md](CHANGELOG.md) | User-visible changes |
| [docs/requirements.md](docs/requirements.md) | Scope, Phase 2 rules, Watch scope |
| [docs/architecture.md](docs/architecture.md) | Tech stack, structure, API, sync, data flow |
| [docs/features.md](docs/features.md) | Implemented features in detail |
| [docs/testing.md](docs/testing.md) | Test practices |
| [docs/security.md](docs/security.md) | Credentials, transport, logging |
| [docs/app-store.md](docs/app-store.md) | Identifiers, entitlements, privacy, export compliance |
| [docs/release.md](docs/release.md) | TestFlight / release checklist |
| [docs/roadmap.md](docs/roadmap.md), [docs/backlog.md](docs/backlog.md) | Planning and next tasks |
| [docs/adr/](docs/adr/README.md) | Architecture Decision Records |
| [docs/history.md](docs/history.md) | Closed investigations and lessons learned |
| [User Guide](https://cookieberlin.github.io/EngelsystemClient/guide) · [FAQ](https://cookieberlin.github.io/EngelsystemClient/faq) · [Privacy Policy](https://cookieberlin.github.io/EngelsystemClient/privacy) · [Support](https://cookieberlin.github.io/EngelsystemClient/support) | Published pages |

## License

[GPL-2.0](LICENSE).
