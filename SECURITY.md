# Security policy

## Reporting a vulnerability

Please **do not open a public issue** for a security problem. Report it privately instead:

- GitHub: **Security → Report a vulnerability** on
  [the repository](https://github.com/cookieBerlin/EngelsystemClient/security/advisories/new), or
- e-mail: [EngelsystemClient@cuccato.net](mailto:EngelsystemClient@cuccato.net)

Please describe what you found, how to reproduce it and which version or build is affected. Do not include other people's
API keys or personal data. You will get an answer as soon as possible; a fix is released with the next version and the
report is credited if you wish.

## Supported versions

Only the latest released version (TestFlight or App Store) receives fixes.

## How the app handles secrets

API keys are stored only in the Keychain, never logged, and sent only to the server you configured over HTTPS without
trust exceptions. Details: [docs/security.md](docs/security.md). What data the app handles is described in the
[privacy policy](docs/privacy.md).

Problems in the Engelsystem server itself belong to the
[Engelsystem project](https://github.com/engelsystem/engelsystem/security).
