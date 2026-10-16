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
fallbacks are deleted again (R tasks). Order of work: K-10 – K-13 (framework, done), then S-01 – S-06 (features with fallbacks),
the W tasks alongside, the R tasks when the owner reports a merge.

### Website (GitHub Pages; each step its own commit)

- [ ] **W-03** With K-11: "Instance features" in the guide, FAQ entries ("Why is an area missing?", "What may my account
      do?"), privacy and support pages.
- [ ] **W-05** Screenshots: new scenes (main screen with groups, shift detail, settings hub, features list) in
      `ScreenshotTests`/`Scripts/screenshots.sh`/`Scripts/publish-guide-images.sh`; refresh `docs/assets/guide/`. The main
      screen and settings first (after W-02), shift detail after S-04, features list after K-11.
- [ ] **W-07** Manual screenshots of **every screen** (planned 2026-10-16), separate from the App Store set: a second UI test
      `ManualScreenshotTests` (demo data, same simulator preparation) walks every screen — main page, each area (shifts incl.
      filter/sort menu and shift detail, news incl. article and comments, profile, locations incl. detail, messages list,
      conversation and new message), Settings hub and every sub-page (Instances, instance page incl. Features list, Add Instance,
      Notifications, Sync, Phone Numbers, Privacy, Diagnostics incl. Watch logs, About), the multi-instance views (sectioned/
      merged, color picker) and the Watch (next shift, settings hub and sub-pages). Output `Screenshots/manual/<device>/NN-<name>.png`;
      `Scripts/screenshots.sh manual` and an extended `Scripts/publish-guide-images.sh` copy them as small PNGs to
      `docs/assets/guide/`; `docs/guide.md` embeds each screen at its place. A checklist in `docs/testing.md` ("new screen =
      new scene") keeps the set complete. Replaces the scenes listed in W-05. Decided 2026-10-16: iPhone and Watch only (iPad only for a screen whose layout differs), English only.
- [ ] **W-08** GitHub issue templates (planned 2026-10-16): `.github/ISSUE_TEMPLATE/` with forms for **Bug report** (what happened /
      expected, steps, app version + build, iOS/watchOS version, device, Engelsystem server version or "demo mode", whether it
      is the iPhone or the Watch, debug log attached — with a warning to check for names before attaching),
      **Feature request** and `config.yml` (blank issues off, links to the guide, FAQ and support page; security issues go to
      the e-mail address, not to a public issue). Also a pull request template pointing at `CONTRIBUTING.md`. Mention the
      template in `docs/support.md`, the FAQ ("how do I report it") and `CONTRIBUTING.md`; check `docs/_config.yml` (the
      `.github` folder is not part of `docs/`). Decided 2026-10-16: attaching the log is optional (with the hint), not a required field.
- [ ] **W-06** After each R task: delete that PR's row from the compatibility table; at R-13 remove the section (the
      privilege explanation stays).

## Removing the compatibility workarounds (R tasks, ADR 0013/0015)

**Fallbacks are temporary.** Every code path, comment and test that exists only because a PR is not merged is tagged
`COMPAT(#<PR>)` (greppable), lives in clearly separated code/test files where possible and is listed in the register in
`docs/architecture.md`. Each R task is its own commit; all gates, both app builds and the UI tests stay green. **Start
condition for every R task:** the owner reports that the PR is merged **and** the servers run it (merged is not
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
