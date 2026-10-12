# 0007. Demo mode through a sentinel base URL inside `APIClient`

- **Status**: Accepted
- **Date**: 2026-09-02 (recorded retroactively 2026-10-12)

## Context

Reviewers and testers have no Engelsystem account or API key, and a mock
server process would add infrastructure.

## Decision

A sentinel base URL (`demo://engelsystem.local`) makes `APIClient` return
static data from `DemoData` instead of doing HTTP. "Try Demo Mode" creates
a normal `Instance` with that URL. Demo data lives only in
`EngelsystemClientKit`'s networking layer, never in views or view models.

## Consequences

- Demo and real instances share every code path except the data source.
- App Store reviewers can use the app end to end
  ([`../release.md`](../release.md)).
- Details: [`../architecture.md`](../architecture.md) (Demo mode).
