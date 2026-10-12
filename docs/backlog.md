# Backlog

Concrete, ready-to-pick-up development tasks (IDs like `T-01`; reference them as
`Backlog: T-01` in commit bodies) — the tactical counterpart
to [`roadmap.md`](roadmap.md)'s strategic/feature-level planning. An
item moves here once it's broken down enough that someone could
actually start on it; it's removed (not just checked off) once it's
done and reflected in [`features.md`](features.md).

## Compatibility with servers lacking the open Engelsystem PRs (see ROADMAP.md)

Each item is its own commit; all gates, both app builds and the UI tests must stay green; tests for everything new.

- [ ] **K-01** Lenient news model: make `comments_count` optional in `EngelsystemClientKit/Resources/openapi.yml` (drop it from
      `required`), regenerate with `Scripts/generate-api.sh`, map a missing value to `nil` → `CachedNews.commentsCount` 0;
      tests (stub network: `/news` without `comments_count` decodes and syncs). Document the local divergence from the upstream
      branch in `docs/architecture.md` (API section) and re-check it after the PRs merge.
- [ ] **K-02** Device-local capability store (`ServerCapabilities`: news comments, locations list, location detail; keyed by
      instance ID, stored in `UserDefaults`/a local file, not CloudKit): API, pure interpretation logic (e.g. "comments
      supported when any `/news` item has `comments_count`; unknown for an empty list keeps the previous value"), updated from
      `AppSyncCoordinator` results and the screens' own fetches; tests. ADR 0013.
- [ ] **K-03** News: show the comments link, `NewsDetailView` and comment counts only when comments are supported; a 404/403
      from `GET /news/{id}` hides the feature silently (marks it unsupported) instead of showing an error; tests (view-model and
      `InstanceScope`-style helpers).
- [ ] **K-04** Locations: hide the Locations sidebar entry unless at least one active instance can list locations (like
      Messages: `MainView.Section.visibleSidebarCases`, fallback selection); a shift's location is plain text without a cached
      location; `LocationDetailViewModel` treats 404/403 as "no refresh available" (no error banner); the list sync's
      404 → empty behavior stays; tests; adapt the UI tests that open Locations.
- [ ] **K-05** Connection check: `APIClient` probes a data endpoint during "Test Connection" (setup and edit, iOS and Watch); a
      403 gives a neutral "the server denied access (403)" message and blocks Save; keep the `self` probe (404 → numeric user ID
      fallback); update `APIError.forbidden`'s wording to a neutral text (this pre-empts the wording part of A-01); tests.
- [ ] **K-06** Reminders: in `AppSyncCoordinator` plan shift reminders whenever every instance's *shift* sync succeeded (new
      `shiftsSucceeded`), independent of News/Profile/Locations/Messages failures; news announcements stay independent too;
      tests.
- [ ] **K-07** Docs and verification: ADR 0013, `docs/architecture.md` ("Compatibility with older servers"), `docs/features.md`,
      FAQ ("Why do I not see comments or locations?" — the app hides what a server does not offer), `CHANGELOG.md`; run
      `Scripts/check-all-coverage.sh`, build iOS/Watch (Debug and Release) and the UI tests (erased simulator).

- [ ] **K-08** Website: add a "Server compatibility" section to `docs/guide.md` (short pointer in `docs/faq.md` and, if useful, on
      the landing page) that says which Engelsystem pull requests the app relies on, their status, and what is unavailable
      without them: [#1709](https://github.com/engelsystem/engelsystem/pull/1709) (open) — without it the account needs the
      server's API privilege/group for every request, otherwise "No API access"; [#1710](https://github.com/engelsystem/engelsystem/pull/1710)
      (open) — without it no news comments and no comment counts; [#1711](https://github.com/engelsystem/engelsystem/pull/1711)
      (open) — without it no per-location refresh (cached location details stay visible); private messages — need a server
      with the messages API (not part of Engelsystem yet). Already merged and therefore not listed as a gap: #1708 (`self` in
      worklogs), #1712. The app hides every feature a server lacks (K-01 – K-04). Keep the statuses current.
- [ ] **A-01** (waiting for upstream) Once the Engelsystem pull requests
      [#1708](https://github.com/engelsystem/engelsystem/pull/1708) (self in worklogs),
      [#1709](https://github.com/engelsystem/engelsystem/pull/1709) (no `api` privilege for `/users/self/*` and `/news`),
      [#1710](https://github.com/engelsystem/engelsystem/pull/1710) (news comments),
      [#1711](https://github.com/engelsystem/engelsystem/pull/1711) (`GET /locations/{id}`) and
      [#1712](https://github.com/engelsystem/engelsystem/pull/1712) (API tests) are all closed/merged (status 2026-10-12:
      #1708 and #1712 merged; #1709, #1710, #1711 open), update the internal docs and the app texts:
      remove the `API`/`Bureaucrat` group wording from the setup hint (`InstanceSetupView`), from `APIError.forbidden`'s
      message and its test, and from `docs/architecture.md` (API section and the 403 handling); change the "not yet merged"
      provenance notes for `/news/{id}`, `/locations/{id}` and `self` worklogs in `docs/architecture.md`/`docs/features.md`
      to "merged"; then check whether the numeric user-ID fallback (`selfReferenceWorks`) is still needed.
      **The website (K-08) lists the open PRs and what is missing without them** — when they are all merged, remove
      or rewrite that section too (and drop the group wording everywhere).

_(No other open tasks. TestFlight: build 0.1.0 (2) is in internal testing and submitted for
Beta App Review as of 2026-10-12; if Apple rejects it, the owner reports the reason here.)_
