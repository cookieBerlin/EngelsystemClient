---
title: Support
---

# Support

Engelsystem Client is a native Apple client for
[Engelsystem](https://github.com/engelsystem/engelsystem/), the
volunteer-management system used by events like the Chaos Communication
Congress.

## Getting help

- **Bug reports and feature requests**: open an issue on GitHub —
  [github.com/cookieBerlin/EngelsystemClient/issues](https://github.com/cookieBerlin/EngelsystemClient/issues).
  Please include: what you expected, what happened instead, your iOS
  version, and (if relevant) a copy of the in-app debug log
  (Settings → Diagnostics → "View Debug Log" → "Copy to Clipboard") or
  an exported diagnostics report (Settings → Diagnostics → "Export
  Diagnostics").
- **Email**: [EngelsystemClient@cuccato.net](mailto:EngelsystemClient@cuccato.net)

## Common questions

**The app can't connect to my Engelsystem server.**
Double-check the server URL and your API key (found in your
Engelsystem account settings on that server). Your account needs the
`API` or `Bureaucrat` group on that server for the app to use its API.

**Shifts/Profile show empty, but News works.**
Some older Engelsystem servers don't support the `self` shortcut for
"my own account" on every endpoint. Open the instance's settings in
the app and use "Test Connection" — if needed, it'll let you enter
your numeric user ID (visible in your profile's URL on the website) as
a fallback.

**I don't have an Engelsystem account to try the app.**
Use "Try Demo Mode" on the first screen — it works entirely with
sample data, no server or account needed.

## Privacy

See the [Privacy Policy](privacy.md) for what data the app handles and
how.

## Source code

This project is open source:
[github.com/cookieBerlin/EngelsystemClient](https://github.com/cookieBerlin/EngelsystemClient),
licensed under [GPL-2.0](https://github.com/cookieBerlin/EngelsystemClient/blob/main/LICENSE).
