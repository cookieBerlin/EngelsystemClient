---
title: User Guide
---

# User Guide

Engelsystem Client is an unofficial companion app for
[Engelsystem](https://github.com/engelsystem/engelsystem/), the volunteer-management system used by events like the
Chaos Communication Congress. It connects directly to your event's Engelsystem server with your own API key; there is no
account with the app's developer and no tracking (see the [Privacy Policy](privacy.md)). Questions? See the
[FAQ](faq.md) or [Support](support.md).

> **Beta:** the app is currently tested through Apple's TestFlight. Join with the TestFlight app on your iPhone or iPad
> (a public link will be added here once it is available). Please report problems through TestFlight's "Send Beta Feedback"
> or on [Support](support.md).

## What the app does (and does not)

- Shows **your own shifts**, the **news**, your **profile** (angel types, work logs), the event's **locations**, and — on
  servers that support it — your **private messages**.
- Reminds you **before a shift starts** with local notifications.
- Works with **several events at once**, and has an **Apple Watch** app that shows your next shift.
- It is **read-only for shifts**: you cannot sign up for or change shifts in the app. That needs support in the Engelsystem
  server first.

## Try it without an account: Demo Mode

On the first screen tap **Try Demo Mode**. The app fills itself with sample data (shifts, news, a few messages) and makes no
network requests. You can leave Demo Mode on, or switch it off and add a real server later in **Settings**.

## Connect your Engelsystem server

1. In a browser, open your event's Engelsystem website, sign in and open your **user settings**. Copy your **API key**
   (the exact wording depends on the server's version). Your account needs the **API** or **Bureaucrat** group on that
   server; if you do not see an API key, ask the Engelsystem administrators.
2. In the app, on the first screen (or **Settings → Add Instance**), enter a **Name** (anything you like), the **Server**
   address (for example `https://engel.example.org`) and your **API key**.
3. Tap **Test Connection**. When it says the connection is verified, tap **Save**.
4. If the server cannot resolve "my own account" automatically, the app shows a **User ID** field after the test: enter your
   numeric user ID (visible in the URL of your profile page).

The API key is stored in the iOS Keychain (synced through iCloud Keychain if you use it) and is only ever sent to the server
you entered.

## The main screen

The main screen is a list of areas. Pull down to refresh everything at once; the tiny progress banner at the top shows what is
syncing. The gear button opens **Settings**.

### Shifts

![Shifts](assets/guide/shifts.png){: width="240"}

Your shifts, grouped by day ("Today", "Tomorrow", …). Each shift shows its time and location; tap the location to read its
description. Pull down to refresh. A small badge shows which instance a shift belongs to when you use several.

### News

![News](assets/guide/news.png){: width="240"}

Announcements from the event. Pinned posts come first. Tap **Read More** to expand long posts and the **comments** link to
read the discussion. The filter button at the top shows only **Meetings** or only other posts.

### Profile

![Profile](assets/guide/profile.png){: width="240"}

Your name, your **angel types** (with a note if you are a supporter or still unconfirmed) and your **work logs** with the
total hours.

### Locations

![Locations](assets/guide/locations.png){: width="240"}

All rooms and places of the event with their descriptions. Tap one for details such as a DECT number.

### Messages

![Messages](assets/guide/messages.png){: width="240"}

Private messages with other helpers. Tap the compose button to start a conversation, tap a conversation to read and reply.
The **Messages** area only appears if at least one of your active servers supports it; if you do not see it, your server is
simply not offering it yet. You can delete your own messages; opening a conversation marks incoming messages as read.

## Settings

![Settings](assets/guide/settings.png){: width="240"}

- **Instances**: all your events. Use the switch to turn an event on or off; tap one to edit its name, server or API key, or to
  remove it (this also removes the data cached for it).
- **Multiple Active Instances**: when more than one event is active, choose how Shifts, News and Profile show them:
  **Merged** (one list, labeled by event), **Switcher** (one event at a time via a control at the top) or **Sectioned**
  (one section per event).
- **Notifications**: the reminder times before each shift ("15 min", …). **Add Reminder** adds more, the red button removes
  one. **Notify on New News** posts a notification when a background sync finds new announcements.
- **Apple Watch Reminders**: the same for your Watch, independently of the iPhone list.
- **Sync**: **Background Sync** sets how often the app may refresh in the background (iOS decides the exact moment, so it can
  take longer than the interval); **Sync on App Start** refreshes when you open the app.
- **Diagnostics**: **Debug Logging**, **View Debug Log** and **Export Diagnostics** for bug reports — see the
  [FAQ](faq.md#something-is-wrong-how-do-i-report-it).

## Apple Watch

![Next Shift on Apple Watch](assets/guide/watch-next-shift.png){: width="160"}
![Watch settings](assets/guide/watch-settings.png){: width="160"}

The Watch app shows only your **next shift** (name, time, location) and works on its own, without the iPhone nearby. Its
**Settings** let you switch events on or off, add an instance directly on the Watch, and set the Watch's reminder times.
Your instances are shared between iPhone and Watch through iCloud.

To add the **complication**: on the Watch, touch and hold the watch face, tap **Edit**, choose a complication slot and pick
**Next Shift** (circular, rectangular and inline styles are available).

## Good to know

- **Reminders** are scheduled from the last sync, so open the app (or pull to refresh) after a schedule change.
- The app only talks to the server you entered. There is no analytics and no advertising.
- **iPad** is supported with a sidebar layout.
- The app is open source (GPL-2.0): [github.com/cookieBerlin/EngelsystemClient](https://github.com/cookieBerlin/EngelsystemClient).
