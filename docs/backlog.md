# Backlog

Concrete, ready-to-pick-up development tasks (IDs like `T-01`; reference them as
`Backlog: T-01` in commit bodies) — the tactical counterpart
to [`roadmap.md`](roadmap.md)'s strategic/feature-level planning. An
item moves here once it's broken down enough that someone could
actually start on it; it's removed (not just checked off) once it's
done and reflected in [`features.md`](features.md).

## Compatibility with servers lacking the open Engelsystem PRs (see ROADMAP.md)

Each item is its own commit; all gates, both app builds and the UI tests must stay green; tests for everything new.

**These workarounds are temporary.** Every code path, comment and test that exists only because the PRs are not merged is
tagged `COMPAT(#<PR>)` (greppable), lives in clearly separated code/test files where possible, and is listed in the
"Compatibility workarounds (temporary)" register in `docs/architecture.md`. Task **R-01** removes them all once the PRs are
closed, so that in the end nothing is optional: a missing comments/locations endpoint or a 403 is a real error again.
Permanent improvements (not tagged): K-06 (reminders independent of News).

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
- [ ] **K-05** Connection check (**temporary workaround, tag `COMPAT(#1709)`**): `APIClient` probes a data endpoint during
      "Test Connection" (setup and edit, iOS and Watch). A 403 shows a **warning that still allows Save** (owner decision
      2026-10-12: the admin may grant access later) and names the cause: the account lacks the server's `api` privilege, so it
      must be added to one of the groups that has it (for example "API" or "Bureaucrat") by the server administrators — **no
      mention of pull requests in the message**. Keep the `self` probe (404 → numeric user ID fallback). `APIError.forbidden`
      gets the same privilege/group wording (replacing today's text); tests.
- [ ] **K-06** Reminders: in `AppSyncCoordinator` plan shift reminders whenever every instance's *shift* sync succeeded (new
      `shiftsSucceeded`), independent of News/Profile/Locations/Messages failures; news announcements stay independent too;
      tests.
- [ ] **K-07** Docs and verification: ADR 0013 (states that the workarounds are temporary and when they go), the "Compatibility workarounds (temporary)" register in `docs/architecture.md` (one row per `COMPAT(#<PR>)` tag: what, where, which PR, how to remove), `docs/architecture.md` ("Compatibility with older servers"), `docs/features.md`,
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
- [ ] **R-01** (blocked until Engelsystem PRs [#1709](https://github.com/engelsystem/engelsystem/pull/1709),
      [#1710](https://github.com/engelsystem/engelsystem/pull/1710) and [#1711](https://github.com/engelsystem/engelsystem/pull/1711)
      are closed/merged — #1708 and #1712 already are; check with `gh pr view <n> --repo engelsystem/engelsystem`) **Remove the
      compatibility workarounds so everything must work again.** Checklist: (1) `grep -rn "COMPAT(" .` and remove every tagged
      path, comment and test; (2) restore the upstream `openapi.yml` (re-fetch from upstream `main`; `comments_count` is
      required again) and regenerate; (3) drop the capability store and all gating of comments and locations (K-02 – K-04):
      comments, `GET /news/{id}`, the Locations area and `GET /locations/{id}` are always shown, and a failure shows a normal
      error banner again; (4) "Test Connection": a 403 on the data probe is a hard error again and blocks Save; (5) remove the
      `API`/`Bureaucrat` group wording from the setup hint, `APIError.forbidden` and its test, and `docs/architecture.md`;
      (6) change the "not yet merged" provenance notes (`/news/{id}`, `/locations/{id}`, `self` worklogs) to "merged"; decide
      with the owner whether the numeric user-ID fallback (`selfReferenceWorks`) can go too (it only matters for servers older
      than #1708); (7) remove the "Server compatibility" section from the website (K-08) and the FAQ pointer, and the register
      in `docs/architecture.md`; (8) the Messages capability probe stays (the messages API is not part of this set); (9) run
      all gates, both builds and the UI tests.

_(No other open tasks. TestFlight: build 0.1.0 (2) is in internal testing and submitted for
Beta App Review as of 2026-10-12; if Apple rejects it, the owner reports the reason here.)_
