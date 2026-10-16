---
title: Privacy Policy
---

# Privacy Policy

**Last updated: 2026-10-12**

This page describes what data the Engelsystem Client app ("the app")
collects and how it's handled. It's kept up to date whenever the app's
data handling changes — if you're reading this to evaluate the app
(e.g. as part of an App Store/TestFlight review), it reflects the
current, shipped behavior.

## Summary

The app has no backend of its own. It talks directly to the
Engelsystem server you choose to connect it to, using an API key you
provide. There is no analytics, no advertising, and no third-party
tracking of any kind. The developer cannot see your shifts, messages,
profile, or any other data you access through the app.

## What data the app handles, and where it goes

- **Your Engelsystem API key**: entered by you, stored in your
  device's Keychain (and, if iCloud Keychain is enabled on your
  device, synced to your other Apple devices via Apple's own iCloud
  Keychain sync — not by this app's developer). It is sent only to the
  Engelsystem server you configure, as an authentication header on
  each request. It is never sent to the app's developer or to any
  third party.
- **Instance settings** (server name/URL
  and a few internal flags describing what that server supports):
  stored via Apple's CloudKit in *your own* private iCloud container,
  so these settings sync between your own iPhone, iPad, and Apple
  Watch. The developer has no access to this data — it lives in your
  iCloud account, governed by Apple's own privacy practices.
- **Shifts, news, your profile, and locations**: fetched from the
  Engelsystem server you configure and cached locally on your device
  (so the app works offline and loads quickly) — never sent anywhere
  except back to that same server on your next sync. The cached
  shifts include the team of a shift (the names of the other angels
  and whether they showed up), as the server shows it to you; they are
  removed together with the instance. The “Sign out in browser” button
  only opens the shift's page in your default browser — the app does
  not sign you out itself.
- **What your account may use**: the app asks your server which privileges your account has (the list the server returns with
  your own user data) and notes, per instance, which functions are available. This result stays on the device where it was
  determined (it is not synced and not sent anywhere except by asking that same server again on the next sync); it is shown in
  Settings → Instances → your instance → Features.
- **Private messages** (on servers that support this feature): fetched
  live from the Engelsystem server each time you open a conversation —
  not cached or stored by the app at all.
- **Local notifications** (shift reminders): generated and scheduled
  entirely on your device. The app has no server-side push
  infrastructure — nothing is sent to Apple's push servers or anywhere
  else for this.
- **Debug log** (on by default in the current beta versions; a switch in
  Settings → Diagnostics turns it off, and the Apple Watch app has its
  own switch; the iPhone can switch the Watch's too): the app records its own internal activity on the device
  where it runs, for troubleshooting.
  - *What it contains:* the time and kind of each event (for example
    "sync started/finished"), error codes, the names you gave your
    instances, the paths of API requests (such as `GET /users/self/shifts`)
    and counts (for example the number of shifts loaded).
  - *What it never contains:* your API key or any other secret, and none
    of the content of your shifts, news, locations or messages.
  - *Where it lives:* a plain text file in the app's cache folder on that
    device, excluded from backups, limited to the most recent entries
    (500 by default, 100–5000 selectable). Turning logging off stops new
    entries; "Clear" in the log view deletes the entries.
  - *How it leaves the device:* only when you do something. You can copy
    it, share it, or — for the Apple Watch's log — send it from the Watch
    to your own iPhone or request it from the iPhone. It then stays on
    your iPhone until you delete it. The app never sends it to any server
    and never uploads it on its own.
- **Crash and performance diagnostics** (via Apple's MetricKit): the
  app subscribes to on-device crash, hang, and performance diagnostics
  that iOS collects about the app's own behavior. These stay on your
  device; the app never transmits them automatically. You can
  explicitly export/share them (Settings → Diagnostics → "Export
  Diagnostics") — for example, to attach to a bug report email — but
  that only happens if you choose to do it, after a screen explaining
  what they contain (device model, iOS and app version, call stacks,
  performance figures — not your API key, shifts, or messages). The
  app keeps these reports on your device for at most 30 days and at
  most 1 MB.
- **Map links**: with the default setting **Settings › Privacy › Map Links = "Link and Embedded Map"**, the app loads the
  map page of a location inside the location screen, from the address your server's organizers entered for it. That request
  goes to whoever runs that map page, which may see your IP address like any website you visit. It happens only when you open
  such a location, the app sends no data of yours along (no API key, no account data), and the page is loaded
  afresh each time. Cookies and similar data the map page stores (for example your consent) stay on your device in a store used
  only by this map view, separate from Safari, and are sent only to that map page; the app deletes them automatically every 30 days by
  default (changeable, never, or only until the app quits, under **Settings › Privacy**), and you can delete them any time under
  **Settings › Privacy › Delete Map Website Data**. Links inside the map page stay in that view and do not open other apps. If you switch the setting to "Link Only", the
  app loads nothing from the map address; tapping "Show Map" opens it in your browser.
- **Demo Mode**: uses entirely synthetic, pre-built sample data and sends nothing to any server. The one exception is
  the map link of the demo location “Workshop Room A”, which points to this project's page on GitHub: it is only loaded
  when you open that location (in the app's map view, or in your browser with “Link Only”), exactly like any other map link.

## What the app does *not* do

- No analytics SDKs, no advertising, no third-party trackers.
- No account is created with the app's developer — you authenticate
  directly against the Engelsystem server you choose, with your own
  credentials.
- No data is sold, shared, or used for advertising.

## The Engelsystem server you connect to

The app is a client for Engelsystem servers operated by event
organizers — not by this app's developer. Once you enter a server's
address and your API key, your requests go directly to that server.
How that server's operator handles your data is governed by their own
policies, not this one; if you have questions about a specific event's
server, contact that event's organizers.

## This website

These pages are static and served by GitHub Pages. They use no cookies, no analytics and no external resources — all files
(including the stylesheet and scripts) come from this site itself. If you switch between light and dark mode, your choice is
stored only in your own browser (local storage) and is never sent anywhere. As the hosting provider, GitHub may process
technical data such as your IP address when you visit; see GitHub's privacy statement.

## Children's privacy

The app is not directed at children and does not knowingly collect
data from children.

## Changes to this policy

This policy is updated whenever the app's actual data handling
changes, alongside the app update that makes the change — not on a
fixed schedule. The "Last updated" date above reflects the most recent
change.

## Contact

Questions, concerns, or a request related to your data:

- Open an issue: [github.com/cookieBerlin/EngelsystemClient/issues](https://github.com/cookieBerlin/EngelsystemClient/issues)
- Email: [EngelsystemClient@cuccato.net](mailto:EngelsystemClient@cuccato.net)
