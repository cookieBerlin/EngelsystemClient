# Backlog

Concrete, ready-to-pick-up development tasks (IDs like `T-01`; reference them as
`Backlog: T-01` in commit bodies) — the tactical counterpart
to [`roadmap.md`](roadmap.md)'s strategic/feature-level planning. An
item moves here once it's broken down enough that someone could
actually start on it; it's removed (not just checked off) once it's
done and reflected in [`features.md`](features.md).

## Removing the compatibility workarounds (see ROADMAP.md, ADR 0013)

The workarounds K-01 – K-08 are implemented and registered in `docs/architecture.md` ("Compatibility workarounds (temporary)"). Each removal task is its own commit; all gates, both app builds and the UI tests must stay green.

**These workarounds are temporary.** Every code path, comment and test that exists only because a PR is not merged is
tagged `COMPAT(#<PR>)` (greppable), lives in clearly separated code/test files where possible, and is listed in the
"Compatibility workarounds (temporary)" register in `docs/architecture.md`. The removal tasks **R-02 (#1709), R-03 (#1710)
and R-04 (#1711)** and **R-06 (#1720)** each remove one PR's workarounds as soon as that PR is merged, so that in the end nothing is optional: a
missing comments/locations endpoint or a 403 is a real error again.

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
- [ ] **R-06** (blocked until [#1720](https://github.com/engelsystem/engelsystem/pull/1720) is merged) Remove the Messages
      capability probe (not tagged `COMPAT`, it predates this convention): `Instance.messagesSupported`, the probe in
      `APIClient.messagesSupported(_:)` and its step in `AppSyncCoordinator`, and the `visibleSidebarCases` hiding of
      `.messages` — Messages is always available and a failure shows a normal error banner (a 403 means the account lacks the
      `user_messages` privilege: say so in the message). Re-fetch the upstream `openapi.yml` for `/messages*` and compare with
      ours (the PR may have changed since it was fetched from the `feat/api-messages` branch); update the "not yet merged"
      provenance note in `docs/architecture.md`; delete the #1720 row of the website section, the FAQ wording and the register
      entry; tests; all gates, builds, UI tests. Check the PR's final behavior for read marking (`GET` does not mark read, our
      app marks via `PATCH`).
- [ ] **R-05** (done by whichever of R-02/R-03/R-04/R-06 finishes last) Final cleanup: delete the device-local capability store
      (`ServerCapabilities`, K-02) once neither comments nor locations use it, the "Server compatibility" section of the website
      with its FAQ pointer, the register section in `docs/architecture.md`, mark ADR 0013 "Superseded" (or amend it), and make
      sure `grep -rn "COMPAT("` finds nothing. (Messages: see R-06; #1712 only added tests.)

_(No other open tasks. TestFlight: build 0.1.0 (2) is in internal testing and submitted for
Beta App Review as of 2026-10-12; if Apple rejects it, the owner reports the reason here.)_
