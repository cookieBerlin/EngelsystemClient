# 0014. Optional embedded map view for location map links

- **Status**: Accepted
- **Date**: 2026-10-13

## Context

A location can carry a map address (`map_url`) chosen by the event organizers. The owner wants a per-device setting that either
shows only the link (opens the system browser) or additionally renders the map page inside the location screen, without
browser chrome. The address is arbitrary web content from a third party, so rendering it inside the app needs limits.

## Decision

- Setting `MapLinkMode` (`embedded` default, `linkOnly`), per device in `UserDefaults` like the sync settings; iOS only.
- `embedded` uses a plain `WKWebView` (system framework, no dependency) inside `LocationDetailView`, not
  `SFSafariViewController` (which has browser chrome).
- Restrictions: only `http`/`https` URLs are loaded or navigated to (`MapLinkMode.embeddableURL`/`allowsNavigation`); the
  page itself is fetched anew every time the screen appears (cache ignored), but cookies and other website data live in a
  persistent store of the map view only (`WKWebsiteDataStore(forIdentifier:)`, apart from Safari and everything else), so a
  provider's consent survives; the app deletes it automatically every N days (setting, default 30, 0 = never, or "Until the App Quits": one in-memory `WKWebsiteDataStore.nonPersistent()` shared for the app run and never written to disk; checked when a location with an embedded map opens, before the map loads), and Settings › Locations › Delete Map Website Data removes all of it after a yes/no confirmation
  (first design was a non-persistent store, changed
  2026-10-13 because the consent dialog reappeared on every visit); the view never receives the API key or any app data; an "Open Map in Browser" button stays visible next to the embedded map.
- Allowed navigations use WebKit's "allow without trying an app link" policy (`WKNavigationActionPolicy.allow` raw value + 2,
  an undocumented value that Firefox and Brave also use; a plain `.allow` is the fallback), and `target=_blank` loads in the
  same view. Otherwise iOS hands addresses such as Google Maps to the installed app via universal links, which left the app in
  the middle of a cookie-consent dialog (found 2026-10-13; reloading tapped links ourselves did not help). Accepted risk: the
  raw value is not public API, so App Review or a future iOS could change it; the fallback only loses this protection.
- Nothing is loaded unless the setting is `embedded` (the default) **and** the user opens a location that has a map address.

## Consequences

The app makes requests to a server other than the Engelsystem server, only on the user's explicit choice; `docs/privacy.md`
says so. The embedded page can run its own scripts inside the web view's sandbox. The view is a thin adapter excluded from
coverage; its decisions are tested in `MapLinkMode`. No Watch support.
