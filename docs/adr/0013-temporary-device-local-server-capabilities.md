# 0013. Temporary, device-local server capabilities for features of unmerged Engelsystem PRs

- **Status**: Accepted (temporary — to be superseded by [0015](0015-per-feature-server-compatibility-and-instance-feature-list.md) when backlog K-10 – K-12 land; final cleanup is R-13)
- **Date**: 2026-10-12

## Context

Three upstream Engelsystem pull requests are still open (plus #1720, the messages API, whose probe predates this ADR and is removed by R-06): #1709 (no `api` privilege for `/users/self/*` and `/news`),
#1710 (`GET /news/{id}` with comments, `comments_count` in the news list) and #1711 (`GET /locations/{id}`, locations
readable without the `api` privilege). Servers without them break parts of the app: the news list failed to decode
(required `comments_count`), comments and the location refresh produced error banners. The owner decided that the app must
keep working against such servers and simply **hide** what a server lacks — but only for as long as the PRs are open.

## Decision

- `comments_count` is optional in our `openapi.yml` copy (a documented local divergence from upstream).
- A small `@Observable` `ServerCapabilities` store in the Kit remembers per instance and per `ServerFeature`
  (`newsComments`, `locationsList`, `locationDetail`) whether the server supports it. It is filled from the **normal syncs**
  (no extra requests): comments are supported when `/news` items carry `comments_count`; the locations list when
  `GET /locations` is not forbidden; location detail when `GET /locations/{id}` succeeds (404/403 mean "no").
  Unknown counts as available, so the UI only hides after a sync proved the lack.
- It is **device-local** (`UserDefaults`), not part of the CloudKit-synced `Instance`: no CloudKit schema change, and every
  device learns the answer from its own syncs. The Messages probe (`Instance.messagesSupported`) is a separate, permanent
  mechanism and stays as it is.
- Every code path that exists only for this is tagged `COMPAT(#<PR>)` and listed in a register in `docs/architecture.md`.
  Backlog tasks R-02 – R-04 remove one PR's workarounds each once it is merged; R-13 (formerly R-05) deletes the store and this ADR's
  mechanism. Afterwards a missing endpoint is a real error again.

## Consequences

- The app works against old and new servers without error banners for missing optional features.
- Extra code, tests and UI branches that are removed again later — acceptable because the removal is planned and greppable.
- A device must have synced once before it hides a feature; a never-synced device briefly shows everything (optimistic default).
- A legitimately deleted location produces a 404 on refresh and marks location detail unsupported until the next success.
