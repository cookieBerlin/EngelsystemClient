# Engelsystem Client

A native Apple client for [Engelsystem](https://github.com/engelsystem/engelsystem/),
the volunteer-management system used by events like the Chaos Communication
Congress. It talks to the official REST API of your Engelsystem instance —
no server-side changes required.

## Features

- View your own shifts, grouped by day
- Read news/announcements, including comments
- View your profile, angel types, and worklogs
- Local reminders before your shifts start (no server push involved)
- Manage multiple Engelsystem instances/events at once
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

This README covers the basics for building and running the app. The full
architecture, implementation status, and decision history are documented
for contributors (human or AI) starting at [`CLAUDE.md`](CLAUDE.md), which
links out to the rest of the [`docs/`](docs) folder.
