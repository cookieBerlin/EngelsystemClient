---
title: FAQ
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

Sign in on your event's Engelsystem website and open the page `/settings/api` (for example
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

### Test Connection warns that the account is “not allowed to use the API (403)”.

The server answered, but denied this account access to its data. Ask the server administrators to add your account to a group
that has the `api` privilege, for example “API” or “Bureaucrat”. On a server with the newer access concept
([#1709](https://github.com/engelsystem/engelsystem/pull/1709)) the web privileges of your account are enough. You can still
save the instance and test again later.

### Why do I not see "Messages"?

Messages need a server that offers the private-message interface, which is the still open Engelsystem change
[#1720](https://github.com/engelsystem/engelsystem/pull/1720), and an account with the `api` or the `user_messages`
privilege. The app checks this during each sync and shows the area only if at least one active server supports it. Demo
Mode always has it.

### What happens when I activate several events?

Shifts, News and Profile show data from all active events. **Settings → Instances → Multiple Active Instances** chooses between one merged
list, a switcher, or one section per event. Each row shows a small badge with its event.

### Can I sign up for or swap shifts?

Not yet. The app is read-only for shifts by design; signing up needs support in the Engelsystem server's API first.

### How do I get back to the main list?

Use the back button at the top left of any screen. The app starts on the main list, or on the last area you used.

### How do I remove an event and its data?

**Settings →** tap the event **→ Remove Instance**. This deletes the saved API key and everything cached for that event on this
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

The Watch app syncs on its own with the same server. Make sure the event is **active** in the Watch app's **Settings**, give it a
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
[GitHub](https://github.com/cookieBerlin/EngelsystemClient/issues), or write to
[EngelsystemClient@cuccato.net](mailto:EngelsystemClient@cuccato.net). Please include what you expected, what happened, your
iOS version, and — if useful — the debug log (**Settings → Diagnostics → View Debug Log → Copy to Clipboard**) or an
**Export Diagnostics** report.
