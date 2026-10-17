---
title: Support
html_title: "Support – Engelsystem Client"
description: "How to get help with the Engelsystem Client app: report a bug, request a feature or contact the developer."
---

# Support

Engelsystem Client is a native Apple client for
[Engelsystem](https://github.com/engelsystem/engelsystem/), the
volunteer-management system used by events like the Chaos Communication
Congress.

## Getting help

- **New to the app?** Read the [User Guide](guide.md); common questions are answered in the [FAQ](faq.md).

- **Bug reports and feature requests**: open an issue on GitHub —
  [github.com/cookieBerlin/EngelsystemClient/issues](https://github.com/cookieBerlin/EngelsystemClient/issues).
  The issue form asks for the details below. Please include: what you expected, what happened instead, your iOS
  version, and (if relevant) a copy of the in-app debug log
  (Settings → Diagnostics → "View Debug Log" → "Copy to Clipboard") or
  an exported diagnostics report (Settings → Diagnostics → "Export
  Diagnostics").
- **Email**: [EngelsystemClient@cuccato.net](mailto:EngelsystemClient@cuccato.net)

## Common questions

More in the [FAQ](faq.md).

**The app can't connect to my Engelsystem server.**
Double-check the server URL and your API key (on your Engelsystem
server open `/settings/api` and press "Show API key"). The app uses
the Engelsystem REST API v0-beta.

**I don't have an Engelsystem account to try the app.**
Use "Try Demo Mode" on the first screen — it works entirely with
sample data, no server or account needed.

**An area (Messages, Locations, news comments) is missing.**
Your server or your account does not offer it (yet); the app hides what is not available. **Settings → Instances →** your
instance → **Features** shows why. See the [FAQ](faq.md#why-do-i-not-see-comments-locations-or-messages) and the
[User Guide](guide.md#what-your-instance-offers-the-features-list).

## Privacy

See the [Privacy Policy](privacy.md) for what data the app handles and
how.

## Source code

This project is open source:
[github.com/cookieBerlin/EngelsystemClient](https://github.com/cookieBerlin/EngelsystemClient),
licensed under [GPL-2.0](https://github.com/cookieBerlin/EngelsystemClient/blob/main/LICENSE).
