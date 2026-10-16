# Security

Rules and current facts about credentials, transport security and
logging. Hard constraints are mirrored in [`CLAUDE.md`](../CLAUDE.md).

## Credentials

- The Engelsystem API key is stored **only in the Keychain**
  (`KeychainSyncStore` for iCloud-synced storage, `LocalKeychainStore`
  for device-local), referenced from `Instance.apiKeyKeychainRef` — never
  in SwiftData, `UserDefaults`, files or CloudKit records. See
  [`app-store.md`](app-store.md) for the shared access group.
- The key is sent only to the instance's own server, as the `x-api-key`
  header (or bearer token), by `APIClient`.
- **Never log** API keys, tokens or full request headers. The debug log
  records the endpoint template and the outcome only.

## Transport

- HTTPS via `URLSession` with the system trust evaluation. The project
  defines no App Transport Security exceptions and no custom
  server-trust handling; do not add trust exceptions for invalid
  certificates.
- Demo mode (`demo://` sentinel URL) makes no API requests; the only web page it can load is the map link of the demo location “Workshop Room A” (the project's GitHub page), when the user opens it.
- The optional embedded map (ADR 0014) loads only `http`/`https` addresses into a `WKWebView` with a persistent data store of its own (apart from Safari, deletable in Settings) and
  gets no app data; App Transport Security still applies, so plain `http` map pages fail to load.

## Data on device and in iCloud

- Cached shifts/news/profile data lives in SwiftData on the device.
  `Instance` metadata (not the key) syncs via CloudKit.
- Private messages are live-only: no local cache, no CloudKit.
- Diagnostics (`MetricKitReporter`, `DebugLog`) stay on the device and
  leave it only when the user exports them manually.

## Repository hygiene

- Public repo under GPL-2.0. Before publishing history or adding fixtures,
  check for keys, personal paths and private hosts (a full audit is
  recorded in [`history.md`](history.md#2026-10-09-pre-public-security-audit)).
- Test fixtures use obviously fake values (`demo-key`, `example.com`).
- Keep [`privacy.md`](privacy.md) in sync with any change here.
