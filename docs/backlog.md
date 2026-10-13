# Backlog

Concrete, ready-to-pick-up development tasks (IDs like `T-01`; reference them as
`Backlog: T-01` in commit bodies) — the tactical counterpart
to [`roadmap.md`](roadmap.md)'s strategic/feature-level planning. An
item moves here once it's broken down enough that someone could
actually start on it; it's removed (not just checked off) once it's
done and reflected in [`features.md`](features.md).

## Server compatibility and the shift detail page (planned 2026-10-13, ADR 0015)

Background: the server side is a stack of open upstream PRs (#1709 – #1726, see the matrix below and
[`roadmap.md`](roadmap.md)). The app must work with upstream `main` today, with each PR and with all of them; missing
rights or functions are **never errors** (silent hiding plus a feature list per instance); once PRs are merged the
fallbacks are deleted again (R tasks). Order of work: K-10 – K-13 (framework), then S-01 – S-06 (features with fallbacks),
the W tasks alongside, the R tasks when the owner reports a merge.

### Framework

- [ ] **K-10** Feature list in the model: `InstanceFeature` (Shifts, News, News comments, Locations, Messages, Profile work
      logs/angel types, Profile goodie score/vouchers, Shift type description, Shift team and freeloaded, Sign-out deadline,
      Refresh a single shift) with a state per instance (`available`, `notAllowed(privilege?)`, `notOffered`, `unknown`),
      source (`privileges` of `GET /users/self`, field present/missing, 404, 403) and "checked at". Device-local like
      `ServerCapabilities` (no CloudKit schema change). Unknown counts as available. Unit tests for every transition.
- [ ] **K-11** UI: "Features" section on the instance detail page (Settings › Instances › [instance]: symbol, name, short
      reason, "Checked: …"); a one-line summary ("5 of 11 features available") after "Test Connection" in the setup and edit
      flows (iOS and Watch setup keep their own wording); refreshed after every sync. Demo mode: everything available.
- [ ] **K-12** Silent hiding: a 403/404 on an optional function becomes "not allowed"/"not offered" and never an error
      banner; sidebar sections without any available active instance disappear (already so for Messages/Locations);
      the "Test Connection" 403 warning (`COMPAT(#1709)`) is removed; remaining messages name web privileges, not the
      `API`/`Bureaucrat` groups; 401, network and server errors stay visible.
- [ ] **K-13** Test fixtures and the matrix: JSON fixtures for "upstream main today", each PR's additions, the stacked
      chains (#1722 → #1723 → #1724) and "all PRs" in `TestSupport`; per feature one test per state (available/hidden, no
      error). Document the matrix in `docs/testing.md`. Coverage stays at 100 %.

### Shift detail page (iOS; the Watch stays unchanged)

- [ ] **S-01** Model: decode the new fields as optional (`openapi.yml` copy patched with `COMPAT(#<PR>)` until merged, then
      re-fetched from upstream): Shift `shift_type.description`, `sign_out_until`, `signup_available_from`, `tags`,
      `talk_url`, `night_shift`; ShiftEntry `freeloaded`, `freeloaded_by`, `can_sign_out`, `user_comment`,
      `freeloaded_comment`. Cache `needed_angel_types` with its entries (encoded field on `CachedShift`, no new model); the
      change detection that wakes the Watch must ignore team-only changes. The own entry is found by the cached profile's
      user id. Fill the so-far empty `angelTypeID`/`angelTypeName`.
- [ ] **S-02** `ShiftDetailView` (iOS) reached from a shift row (the location link stays in the row): header (title, time,
      duration, location with link), shift type name + description, the shift's own description, optional tags / night
      shift hint / talk link button / "sign-up from". Display texts as tested static functions.
- [ ] **S-03** Team section grouped by angel type: occupancy "n of m" (overbooked or additional-only types show the count),
      names, the own entry highlighted, "did not show up" from `freeloaded` (fallback `freeloaded_by != null`,
      `COMPAT(#1723)`), "by <name>" only when `freeloaded_by` is present. Long teams collapse above about ten names.
- [ ] **S-04** "Sign out until <time>" from `sign_out_until`; the button "Sign out in browser" (opens the shift's web `url` in
      the default browser; hidden without a known URL) is shown on the own entry when `can_sign_out` is true. Fallback
      without the fields (`COMPAT(#1722)`/`COMPAT(#1723)`): "usually until 3 hours before the start" and the button while
      that time is in the future. The app never signs out by itself (no Phase 2 write feature).
- [ ] **S-05** Pull to refresh on the detail page via `GET /shifts/{id}` (`COMPAT(#1724)`: 404 ⇒ "not offered", the page
      shows the cached shift without an error).
- [ ] **S-06** Docs: `docs/features.md`, the guide ("Shift details", "Instance features"), the privacy page (names of team
      members are cached on the device, the sign-out link only opens the browser), `CHANGELOG.md`, and the FAQ.

### Website (GitHub Pages; each step its own commit)

- [ ] **W-01** Rewrite the "Server compatibility" table in `docs/guide.md`: one row per PR (#1709 – #1726, status, what is
      missing without it), a short "which privileges do I need?" paragraph (`news`, `locations.view`, `user_shifts`,
      `angeltypes.view`, `user_messages` or `api`; the default group "Angel" has them), reword the FAQ "Why do I not see
      …?" and the "403" entry to the new behaviour. Rows for #1721 – #1726 are marked "planned feature".
- [ ] **W-02** Guide and start page for what is already built: main screen groups and order, Settings pages, phone numbers,
      embedded map, Privacy page; `docs/index.html` feature list.
- [ ] **W-03** With K-11: "Instance features" in the guide, FAQ entries ("Why is an area missing?", "What may my account
      do?"), privacy and support pages.
- [ ] **W-04** With S-06: shift details in the guide, the start page and the privacy page.
- [ ] **W-05** Screenshots: new scenes (main screen with groups, shift detail, settings hub, features list) in
      `ScreenshotTests`/`Scripts/screenshots.sh`/`Scripts/publish-guide-images.sh`; refresh `docs/assets/guide/`. The main
      screen and settings first (after W-02), shift detail after S-04, features list after K-11.
- [ ] **W-06** After each R task: delete that PR's row from the compatibility table; at R-13 remove the section (the
      privilege explanation stays).

## Removing the compatibility workarounds (R tasks, ADR 0013/0015)

**Fallbacks are temporary.** Every code path, comment and test that exists only because a PR is not merged is tagged
`COMPAT(#<PR>)` (greppable), lives in clearly separated code/test files where possible and is listed in the register in
`docs/architecture.md`. Each R task is its own commit; all gates, both app builds and the UI tests stay green. **Start
condition for every R task:** the owner reports that the PR is merged **and** the event servers run it (merged is not
deployed). Afterwards the feature is assumed to exist: a failure shows a normal error again where the privilege list does not
explain it, the fixture state of that PR is deleted and the tests are simplified, its row leaves the website table
(W-06) and the register. The privilege-based part of the feature list (K-10 – K-12) stays for good.

- [ ] **R-02** [#1709](https://github.com/engelsystem/engelsystem/pull/1709) (access concept): remove `COMPAT(#1709)` — the
      403 probe and the `API`/`Bureaucrat` wording, the fallback when `privileges` is missing from `GET /users/self`,
      `freeloaded_by`-based detection of freeloading if still present.
- [ ] **R-03** [#1710](https://github.com/engelsystem/engelsystem/pull/1710) (news comments): restore the upstream
      `openapi.yml` (`comments_count` required), remove the optional-field handling, the comments capability and the hiding.
- [ ] **R-04** [#1711](https://github.com/engelsystem/engelsystem/pull/1711) (locations): remove the locations capabilities
      and hiding; `GET /locations/{id}` refresh is always available.
- [ ] **R-06** [#1720](https://github.com/engelsystem/engelsystem/pull/1720) (messages): remove
      `Instance.messagesSupported`, the probe in `APIClient.messagesSupported(_:)` and its sync step, and the hiding of
      `.messages`; re-fetch the upstream `/messages*` spec and compare. (GET works with `api` or `user_messages`, writes need
      `user_messages`.)
- [ ] **R-07** [#1721](https://github.com/engelsystem/engelsystem/pull/1721) (shift types): remove fallbacks around
      `GET /shifttypes` and `signup_advance_hours` handling.
- [ ] **R-08** [#1722](https://github.com/engelsystem/engelsystem/pull/1722) (shift lists and details): remove the optional
      handling of `shift_type.description`, `sign_out_until`, `signup_available_from`, `tags`, `talk_url`, `night_shift`
      and the "usually 3 hours" assumption.
- [ ] **R-09** [#1723](https://github.com/engelsystem/engelsystem/pull/1723) (shift entry details): remove the
      `freeloaded`/`can_sign_out` fallbacks.
- [ ] **R-10** [#1724](https://github.com/engelsystem/engelsystem/pull/1724) (`GET /shifts/{id}`): remove the 404 handling of
      the single-shift refresh.
- [ ] **R-11** [#1725](https://github.com/engelsystem/engelsystem/pull/1725) (angel types): remove the fallbacks for
      `requires_driver_license`, `requires_ifsg_certificate`, `shift_self_signup` and `GET /angeltypes/{id}`.
- [ ] **R-12** [#1726](https://github.com/engelsystem/engelsystem/pull/1726) (users/profiles): remove the fallbacks for
      `goodie_score`, `vouchers`, `arrived`, `next_shift`, `groups`.
- [ ] **R-13** (after the last of the above) Final cleanup: remove the field/404-based detection that is left, keep the
      privilege-based feature list, delete the "Server compatibility" section of the website (keep the privilege
      explanation), the register section in `docs/architecture.md`, mark ADR 0013 and 0015's temporary parts as done, and
      make sure `grep -rn "COMPAT("` finds nothing.

_(No other open tasks.)_
