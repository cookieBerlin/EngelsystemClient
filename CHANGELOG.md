# Changelog

All notable user-visible changes are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
versioning: [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- Shift details: tapping a shift opens a page with the shift type and its description, the team by angel type ("2 of 3",
  your own entry highlighted, "did not show up" marks), tags, night-shift hint, talk link and — on your own shifts —
  until when you can sign out, with a button that opens the shift in the browser (the app never signs out by itself).
  Servers without the newer fields show what they have.
- Phone numbers (DECT and mobile, on a location and in your profile) can be tapped to call and copied. Numbers of up to five
  digits count as internal; Settings › Phone Numbers chooses the app for internal and for other numbers: the system default
  (`sip:` / `tel:`), Acrobits Softphone, Groundwire, Cloud Softphone (with an action such as preparing the number or a video
  call), a custom link template, or copy only. Your profile now shows your DECT and mobile numbers.
- Settings › Privacy › Map Links: a location's map page is shown inside the location screen
  (almost full screen, loaded fresh every time) with an “Open Map in Browser” button; the setting can be switched to a plain
  link. The map page's cookies, such as a consent, are kept on the device apart from Safari; They are deleted automatically every 30 days
  (changeable, or kept only until the app quits) and Settings › Privacy › Delete Map Website Data removes them at once.

- The main list shows at the bottom how old each active instance's data is (grey below 12 hours, an orange warning from 12 hours, red when
  nothing was loaded yet); tap a line to refresh that instance.
- Switching an instance on in Settings now refreshes it right away (on the iPhone and on the Watch), instead of showing old data until
  the next sync.

- The sync banner shows every instance on its own line with the area it is working on, a thin progress line and "n/5" steps. An
  instance that does not answer for 30 seconds turns orange, one that makes no progress for a minute is stopped so the others can
  continue. Active instances are now refreshed at the same time; **Parallel Syncs** (Settings › Instances, also on the Watch) limits how many
  at once. **Stop sync** (with a confirmation, and **Skip <instance>** when several instances sync) ends a sync that hangs.

- The Features list of an instance is folded away while everything works (tap the summary to open it) and opens by itself, with the
  problems first, as soon as something is missing.

- The Shifts screen has a filter menu: show Upcoming shifts (default), Today, Past or All, and sort Earliest First or Latest First.
  Your choice is remembered on this device.

- Every instance has a color (Settings › Instances › [instance] › Color; "Auto" by default, synced between your devices). With several
  instances the lists show them under a colored band that folds the entries away, merged lists mark the entries with a colored badge and edge,
  and the Profile screen shows the same three topics in every display mode.

- Merged lists: the same location on several instances of one server is shown once with a badge per instance, entries that
  several instances share carry no color edge, and Locations get the badge and edge like the other lists. The Profile band no longer shows a count.
- Demo Mode can have several instances: `demo://engelsystem.local` (as before) and `demo://congress.local`; any other `demo://`
  address plays a server that offers only News, with one post that lists the addresses that work.

- The main list hides every area an instance does not offer (not only Messages and Locations): an instance with only News
  shows just News, without empty Event and Account groups.

- Messages of several instances in the merged list no longer show the same conversation twice, and keep the instance's badge and
  color edge when only one of the active instances offers Messages.

- An instance has one page for everything: name, server and API key are edited right on it (the separate "Edit Instance" screen
  is gone). **Save** and **Discard** (with a confirmation) appear once something changed; saving works without a successful
  connection test. The same on the Apple Watch.
- Demo addresses (`demo://…`) need no API key any more, and "Try Demo Mode" is the first block when adding an instance.

- The colors in the instance's color picker are shown in their own color instead of black.

- Debug logging is on by default in the beta versions (iPhone; Watch follows), so a bug report always has a log. The privacy policy now describes exactly what the log contains and how it leaves the device.

### Removed
- The “Open on Website” button on the location screen.
- The manual “User ID” field and the automatic check for servers without the `self` shortcut: servers that lack Engelsystem's
  “my own account” support for work logs are no longer supported.

### Changed
- Missing rights or functions are no longer shown as errors: areas the server or your account does not offer are simply
  hidden. Settings › Instances › [instance] has a **Features** list that shows what is available and why something is not;
  “Test Connection” shows a short summary instead of the former 403 warning.
- The main screen is grouped: Communication (News, Messages), Event (Shifts, Locations) and Account (Profile). An area that
  is no longer available sends you back to the main screen instead of to Shifts.
- Settings are reorganised into pages: Instances (with Multiple Active Instances), Notifications, Sync (now also showing the
  iCloud status and the last background sync), Phone Numbers, Privacy (map links and deleting map data), Diagnostics and
  About (version and links to the guide, support, privacy policy and source code). The main Settings page shows a short
  summary for each page.
- Works with Engelsystem servers that lack some newer API features: news without comment counts still load, news comments and
  the Locations area are hidden when a server does not provide them, and shift reminders no longer depend on News or Profile
  syncing successfully.
- "Test Connection" now also checks a real data request and warns when the account is not allowed to use the API (403).
- The Features list of the demo instance no longer shows “Not checked yet” for every entry, and “Verify” in Edit Instance
  now also updates that list with what it found. Both show the same summary, including how many entries are not checked yet.
- The demo location “Workshop Room A” has a map link (this project's GitHub page), so the map view can be tried in Demo Mode.
- Fixed: shifts could not be read from servers that send shift tags (“Could not read the API response”). Reading errors now
  also name the field that did not match.

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
