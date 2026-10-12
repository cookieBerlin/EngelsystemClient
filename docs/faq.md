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

### Where do I find my API key?

On your event's Engelsystem website, open your user settings while signed in. The API key is shown there (the exact label
depends on the server's version). Your account also needs the **API** or **Bureaucrat** group on that server; if the key is
missing, ask the event's Engelsystem administrators.

### The app cannot connect to my server.

Check the server address (including `https://`) and the API key, then use **Test Connection** again. If it still fails, the
message under the button tells you the reason: a rejected key (wrong or expired), a missing group ("No API access"), an
unreachable server, or an invalid address.

### Shifts or Profile are empty, but News works.

Some older Engelsystem servers do not support the "my own account" shortcut on every endpoint. Open the instance in
**Settings**, tap **Edit Instance** and run **Test Connection**; if needed the app then asks for your numeric user ID (visible
in the URL of your profile page).

## Using the app

### Why do I not see "Messages"?

Messages need a server that offers the private-message interface. The app checks this during each sync and shows the area only
if at least one active server supports it. Demo Mode always has it.

### What happens when I activate several events?

Shifts, News and Profile show data from all active events. **Settings → Multiple Active Instances** chooses between one merged
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
