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
- **Instance settings** (server name/URL, an optional numeric user ID,
  and a few internal flags describing what that server supports):
  stored via Apple's CloudKit in *your own* private iCloud container,
  so these settings sync between your own iPhone, iPad, and Apple
  Watch. The developer has no access to this data — it lives in your
  iCloud account, governed by Apple's own privacy practices.
- **Shifts, news, your profile, and locations**: fetched from the
  Engelsystem server you configure and cached locally on your device
  (so the app works offline and loads quickly) — never sent anywhere
  except back to that same server on your next sync.
- **Private messages** (on servers that support this feature): fetched
  live from the Engelsystem server each time you open a conversation —
  not cached or stored by the app at all.
- **Local notifications** (shift reminders): generated and scheduled
  entirely on your device. The app has no server-side push
  infrastructure — nothing is sent to Apple's push servers or anywhere
  else for this.
- **Debug log** (off by default, toggled in Settings): if you turn it
  on, the app records its own internal sync/notification activity on
  your device, for troubleshooting. It never includes your API key or
  any other secret. It stays on your device unless you explicitly copy
  it (e.g. to attach to a support request) — the app never sends it
  anywhere on its own.
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
- **Demo Mode**: uses entirely synthetic, pre-built sample data. No
  network requests are made at all while using Demo Mode.

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
