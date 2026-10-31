---
title: FAQ
html_title: "FAQ – Engelsystem Client"
description: "Answers to common questions about the Engelsystem Client app: supported servers, missing areas, notifications, Apple Watch and privacy."
toc: true
---

# Frequently Asked Questions

New to the app? Start with the [User Guide](guide.md). Anything not answered here: [Support](support.md).

## Getting started

### How do I join the beta?

Open the [TestFlight invitation](https://testflight.apple.com/join/Ksn65tz9) on your iPhone or iPad. TestFlight (Apple's free app) asks you to install the app and
keeps it up to date. You can send feedback with screenshots from inside TestFlight.

### I do not have an Engelsystem account. Can I still try the app?

Yes. Tap **Try Demo Mode** on the first screen. It uses built-in sample data and needs no server and no API key.

### Which Engelsystem API does the app use?

The app uses Engelsystem's REST API **v0-beta** (`/api/v0-beta` on your server). That API is still marked as beta by the
Engelsystem project, so details can change with the server's version — newer servers may offer more (for example private
messages), and the app adapts: areas a server does not support are simply not shown.

### Where do I find my API key?

Sign in on your instance's Engelsystem website and open the page `/settings/api` (for example
`https://engel.example.org/settings/api`). Press the **Show API key** button and copy the key into the app. Treat it like a
password; if it ever leaks, reset it on the same page.

### The app cannot connect to my server.

Check the server address (including `https://`) and the API key, then use **Test Connection** again. If it still fails, the
message under the button tells you the reason: a rejected key (wrong or expired), an account the server denies API access (403), an
unreachable server, or an invalid address.

## Using the app

### Why do I not see comments, locations or messages?

The app only shows what your server offers and what your account may use. News comments, the Locations area and Messages
depend on Engelsystem changes that are partly still open pull requests; see
[Server compatibility](guide.md#server-compatibility) for the list and status, and for the privileges an account needs.
Nothing is wrong with the app — the area appears automatically after a sync once your server and your account allow it.

### Where can I see what my account may use?

Open **Settings → Instances →** your instance. The **Features** list shows for every area whether it is available, not allowed
for your account (with the privilege it needs, when the server tells) or not offered by the server, and when it was checked.
The list is folded away while everything works (tap the summary line to open it) and opens by itself, problems first, as soon as
something is missing. Missing areas are hidden quietly — the app does not show errors for them. After **Test Connection** a server with the newer
access concept ([#1709](https://github.com/engelsystem/engelsystem/pull/1709)) also shows a short summary such as “5 of 8
features available”.

### Why do I not see "Messages"?

Messages need a server that offers the private-message interface, which is the still open Engelsystem change
[#1720](https://github.com/engelsystem/engelsystem/pull/1720), and an account with the `api` or the `user_messages`
privilege. The app checks this during each sync and shows the area only if at least one active server supports it. Demo
Mode always has it.

### How do I change the color of an instance?

**Settings → Instances →** tap the instance **→ Color**. "Auto" gives every instance its own color; pick one yourself and it is kept, also on your other devices.
Tap the colored band of an instance in the "Sectioned" view to fold its entries away.

### What happens when I activate several instances?

Shifts, News and Profile show data from all active instances. **Settings → Instances → Multiple Active Instances** chooses between one merged
list, a switcher, or one section per instance. Each row shows a small badge with its instance.

### Does the app run on a Mac?

Yes, on a Mac with Apple silicon, as the iPhone/iPad app: install the beta with the TestFlight app on the Mac. This is not tested
in depth yet, so please report anything that looks or behaves wrongly (see [Support](support.md)). The Apple Watch functions are
not part of it.

### Can I sign up for or swap shifts?

Not yet. The app is read-only for shifts by design; signing up needs support in the Engelsystem server's API first.

### Can I sign out of a shift in the app?

No. The shift details show until when you can sign out; **Sign out in browser** opens the shift on the Engelsystem website,
where you do it. Whether the time comes from the server or is the usual “3 hours before the start” depends on the server
version (see the **Features** list of the instance).

### How do I get back to the main list?

Use the back button at the top left of any screen. The app starts on the main list, or on the last area you used.

### What does the line at the bottom of the main list mean?

It shows how old the saved data of each active instance is. Grey with a check mark means less than 12 hours; orange with a warning triangle
means 12 hours or more; red means nothing was loaded yet. Tap a line to refresh that instance. Switching an instance on in Settings refreshes it
automatically, so you do not see old data for long.

### The sync seems stuck. What can I do?

While a sync runs, the banner at the top shows every instance with what it is doing. A line turns orange when a step has not answered
for 30 seconds, and an instance that makes no progress for a minute is stopped (“timed out”) so the others can continue. Tap **Stop sync**
in the banner to end the whole sync, or choose **Skip <instance>** to leave out just the one that hangs. Data that was already loaded is kept.

Instances are refreshed at the same time by default. If that is too much for a weak connection, lower **Settings → Instances → Parallel Syncs** (the Watch has the same setting).

### Where are my past shifts?

The Shifts screen lists upcoming and running shifts by default. Open the filter menu at the top right and choose **Past** (or **Today**, **All**);
there you can also sort **Latest First**. The choice is remembered on this device.

### Can I try several instances in Demo Mode?

Yes. Add instances with the server address `demo://engelsystem.local` or `demo://congress.local` (any name; no API key is needed). The same address
counts as one server, so shared locations and news are shown once; a different address is a different server. Any other `demo://` address plays a server that offers only News
and shows one post that lists the addresses that work; every other area stays hidden.

### How do I remove an instance and its data?

**Settings →** tap the instance **→ Remove Instance**. This deletes the saved API key and everything cached for that instance on this
device.

## Notifications

### Why did I not get a reminder?

- Allow notifications for the app in iOS Settings.
- Reminders are scheduled from the **last sync** — open the app or pull to refresh after a schedule change.
- Check **Settings → Notifications** for the reminder times; the Watch has its own list under **Apple Watch Reminders**.
- A reminder is only created for shifts that have not started yet and whose time before the start has not already passed.
- Background refresh is up to iOS; it can be delayed by battery saving or low usage.

## Apple Watch

### The Watch shows no shift.

The Watch app syncs on its own with the same server. Make sure the instance is **active** in the Watch app's **Settings**, give it a
moment after opening, and check that iCloud is signed in on both devices (instances are shared through iCloud). If you
do not use iCloud, add the instance directly in the Watch app (**Settings → Add Instance**).

### How do I add the complication?

Touch and hold the watch face, tap **Edit**, select a complication slot and choose **Next Shift**.

## Privacy and data

### What data does the app collect?

None on a server of the developer — there is none. Your API key stays in your Keychain and goes only to your own server.
Details: [Privacy Policy](privacy.md).

### Is my data synced?

Instance names and server addresses (not your shifts or messages) sync between your own devices via iCloud, and your API key
via iCloud Keychain if you use it. Shifts, news and profile are cached on each device separately; messages are never stored.

## Something is wrong: how do I report it?

Use TestFlight's **Send Beta Feedback** (screenshots welcome) or open an issue on
[GitHub](https://github.com/cookieBerlin/EngelsystemClient/issues) (a form asks for the details; security problems go to the
[security policy](https://github.com/cookieBerlin/EngelsystemClient/security/policy) instead), or write to
[EngelsystemClient@cuccato.net](mailto:EngelsystemClient@cuccato.net). Please include what you expected, what happened, your
iOS version, and — if useful — the debug log (**Settings → Diagnostics → View Debug Log → Copy to Clipboard**) or an
**Export Diagnostics** report. For the Apple Watch, tap **Settings → Diagnostics → Send Log to iPhone** on the Watch (or **Request Log from
Apple Watch** on the iPhone); the log then appears under **Logs received from Apple Watch**, where you can share all of them at once.
