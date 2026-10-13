# Changelog

All notable user-visible changes are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
versioning: [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- Settings › Locations › Map Links: a location's map page is shown inside the location screen
  (almost full screen, loaded fresh every time) with an “Open Map in Browser” button; the setting can be switched to a plain
  link. The map page's cookies, such as a consent, are kept on the device apart from Safari; They are deleted automatically every 30 days
  (changeable, or kept only until the app quits) and Settings › Locations › Delete Map Website Data removes them at once.

### Removed
- The “Open on Website” button on the location screen.
- The manual “User ID” field and the automatic check for servers without the `self` shortcut: servers that lack Engelsystem's
  “my own account” support for work logs are no longer supported.

### Changed
- Works with Engelsystem servers that lack some newer API features: news without comment counts still load, news comments and
  the Locations area are hidden when a server does not provide them, and shift reminders no longer depend on News or Profile
  syncing successfully.
- "Test Connection" now also checks a real data request and warns when the account is not allowed to use the API (403).

## [0.1.0] - 2026-10-12

First TestFlight build (version 0.1.0, build 2).

### Added
- Shifts: your own shifts grouped by day, with local reminders before they start.
- News with comments and a Meetings / Non-Meetings filter.
- Profile with angel types and worklogs.
- Locations: browse rooms, linked from each shift.
- Private messages on instances whose server supports them.
- Multiple Engelsystem instances, synced between your devices via iCloud;
  the API key is kept in the iCloud-synced Keychain.
- Demo mode ("Try Demo Mode") to try the app without a server or API key.
- Apple Watch app showing the next shift, with a complication and full
  settings; background refresh keeps its data fresh.
- Configurable background sync.
- Debug log (Settings › Diagnostics) and on-device crash/diagnostics
  reports via MetricKit that you can export manually after a screen
  explaining what they contain; they are kept on the device for at most
  30 days / 1 MB, and nothing is sent automatically.
- Privacy Policy and Support pages published via GitHub Pages.

[Unreleased]: https://github.com/cookieBerlin/EngelsystemClient/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/cookieBerlin/EngelsystemClient/releases/tag/v0.1.0
