# Backlog

Concrete, ready-to-pick-up development tasks (IDs like `T-01`; reference them as
`Backlog: T-01` in commit bodies) — the tactical counterpart
to [`roadmap.md`](roadmap.md)'s strategic/feature-level planning. An
item moves here once it's broken down enough that someone could
actually start on it; it's removed (not just checked off) once it's
done and reflected in [`features.md`](features.md).

## Compatibility with servers lacking the open Engelsystem PRs (see ROADMAP.md)

Each item is its own commit; all gates, both app builds and the UI tests must stay green; tests for everything new.

**These workarounds are temporary.** Every code path, comment and test that exists only because a PR is not merged is
tagged `COMPAT(#<PR>)` (greppable), lives in clearly separated code/test files where possible, and is listed in the
"Compatibility workarounds (temporary)" register in `docs/architecture.md`. The removal tasks **R-02 (#1709), R-03 (#1710)
and R-04 (#1711)** each remove one PR's workarounds as soon as that PR is merged, so that in the end nothing is optional: a
missing comments/locations endpoint or a 403 is a real error again. **R-01** (the user-ID / `self` workaround, #1708) is not
blocked — #1708 is merged and servers without it are not supported — and should be done **first**.
Permanent improvements (not tagged): K-06 (reminders independent of News).

- [ ] **K-04** Locations: hide the Locations sidebar entry unless at least one active instance can list locations (like
      Messages: `MainView.Section.visibleSidebarCases`, fallback selection); a shift's location is plain text without a cached
      location; `LocationDetailViewModel` treats 404/403 as "no refresh available" (no error banner); the list sync's
      404 → empty behavior stays; tests; adapt the UI tests that open Locations.
- [ ] **K-05** Connection check (**temporary workaround, tag `COMPAT(#1709)`**): `APIClient` probes a data endpoint during
      "Test Connection" (setup and edit, iOS and Watch). A 403 shows a **warning that still allows Save** (owner decision
      2026-10-12: the admin may grant access later) and names the cause: the account lacks the server's `api` privilege, so it
      must be added to one of the groups that has it (for example "API" or "Bureaucrat") by the server administrators — **no
      mention of pull requests in the message**. The `self` probe and the numeric user-ID fallback are gone by then (R-01); the data probe replaces it. `APIError.forbidden`
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
- [ ] **R-01** (not blocked
- [ ]  — do first) **Remove the user-ID / `self` workaround** (Engelsystem PR #1708, merged; servers without it
      are not supported, owner decision 2026-10-12; no CloudKit schema backward compatibility is needed either): drop
      `Instance.userID` and `Instance.selfReferenceWorks`, `Instance.userReference`/`UserReference.id(…)` (always `self`),
      `APIClient.selfUserReferenceWorks` and its pure interpretation helper, the "User ID" fields and the
      `selfReferenceWorks` handling in the iOS setup/edit screens and the Watch setup/edit/settings views and view models, the
      `userID` parameters of `InstanceSetupService` (`createInstance`, `updateInstance`, including "force-clear userID when self
      works"), the `userID` mentions in `ShiftsViewModel`/`ProfileViewModel`/`NextShiftViewModel` logging and `APIEndpoint`, the
      related tests, `docs/architecture.md` (instance model, setup flow; the `self`/user-ID investigation notes → move to
      `docs/history.md`), the FAQ entry "Shifts or Profile are empty, but News works" (also in `docs/support.md`) and the guide's
      step about the User ID field, and the "worklogs `self`" provenance note ("merged"). Then run all gates, both builds and the UI tests.
- [ ] **R-02** (blocked until [#1709](https://github.com/engelsystem/engelsystem/pull/1709) is merged) Remove `COMPAT(#1709)`:
      the "Test Connection" 403 warning becomes a hard error again and blocks Save; remove the `API`/`Bureaucrat` group wording
      from the setup hint, `APIError.forbidden`'s message and its test, and from `docs/architecture.md`; delete the #1709 row of
      the website's "Server compatibility" section and of the register; tests; all gates, builds, UI tests.
- [ ] **R-03** (blocked until [#1710](https://github.com/engelsystem/engelsystem/pull/1710) is merged) Remove `COMPAT(#1710)`:
      restore the upstream `openapi.yml` (re-fetch from upstream `main`; `comments_count` is required again) and regenerate;
      remove the news-comments capability and all hiding of comments — the comments link, `GET /news/{id}` and the comments
      screen are always available and a failure shows a normal error banner again; update the "not yet merged" provenance note
      for `/news/{id}`; delete the #1710 row of the website section and of the register; tests; all gates, builds, UI tests.
- [ ] **R-04** (blocked until [#1711](https://github.com/engelsystem/engelsystem/pull/1711) is merged) Remove `COMPAT(#1711)`:
      remove the locations capabilities and all hiding of locations — the Locations area and `GET /locations/{id}` refresh are
      always available and a failure shows a normal error banner again; update the "not yet merged" provenance note for
      `/locations/{id}`; delete the #1711 row of the website section and of the register; tests; all gates, builds, UI tests.
- [ ] **R-05** (done by whichever of R-02/R-03/R-04 finishes last) Final cleanup: delete the device-local capability store
      (`ServerCapabilities`, K-02) once neither comments nor locations use it, the "Server compatibility" section of the website
      with its FAQ pointer, the register section in `docs/architecture.md`, mark ADR 0013 "Superseded" (or amend it), and make
      sure `grep -rn "COMPAT("` finds nothing. The Messages capability probe stays — the messages API is not part of this set
      (#1712 only added tests).

_(No other open tasks. TestFlight: build 0.1.0 (2) is in internal testing and submitted for
Beta App Review as of 2026-10-12; if Apple rejects it, the owner reports the reason here.)_
