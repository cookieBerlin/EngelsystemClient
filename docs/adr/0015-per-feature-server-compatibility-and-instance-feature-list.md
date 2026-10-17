# 0015. Per-feature server compatibility and a feature list per instance

- **Status**: Proposed (planned 2026-10-13, not built yet; supersedes [0013](0013-temporary-device-local-server-capabilities.md) once K-10 – K-12 are done)
- **Date**: 2026-10-13

## Context

Engelsystem's REST API is changing through a stack of open upstream pull requests: #1709 (access concept; `GET /users/self`
gains `groups` and `privileges`), #1710 (news comments), #1711 (location detail), #1720 (messages), #1721 (shift types),
#1722 (shift lists and details), #1723 (shift entry details), #1724 (`GET /shifts/{id}`), #1725 (angel types) and #1726
(users/profiles). Servers will run any mix of "current upstream `main`" and servers that include some or all of them,
and an account may lack a web privilege (`news`, `locations.view`, `user_shifts`, `angeltypes.view`, `user_messages`, …).
ADR 0013 handled three PRs with a temporary capability store; the owner now wants maximum compatibility for the whole set
and no errors for missing rights.

## Decision

1. **Per-feature detection, never a server version.** Each app feature decides on its own whether it is available:
   - the field is present in the response (all new fields are decoded as optional),
   - the new endpoint answers (404 ⇒ not offered),
   - the account's `privileges` from `GET /users/self` (when present) or a 403 ⇒ not allowed.
   Unknown means "available" until a request shows otherwise.
2. **Missing rights or functions are not errors.** A 403/404 on an optional function hides the function silently: no banner,
   no warning in "Test Connection". Real failures stay visible: 401 (invalid key, with the redirect to Settings), no
   connection, a broken server.
3. **The instance explains itself.** Settings › Instances › [instance] has a "Features" list with one row per function and
   one of three states: available, not allowed (the server knows it, the account may not; with the privilege name when
   known) and not offered (the server is older). "Test Connection" shows a short summary ("5 of 11 features available").
   Sections without any available instance disappear from the sidebar completely.
4. **Fallbacks are temporary, the list is permanent.** Every fallback that exists only because a PR is not merged is tagged
   `COMPAT(#<PR>)`, registered in `docs/architecture.md`, and removed by its own R task once the owner reports that the PR is
   merged **and** the servers run it. The privilege-based part of the feature list stays for good, because an account
   can always lack a privilege.
5. **Tests as a matrix.** Fixtures describe "upstream main today", each PR's additions, the stacked chains (#1722 → #1723 →
   #1724) and "all PRs". Every feature has a test per state; removing a PR removes its fixture state.

## Consequences

- The app works against old and new servers and tells the user why something is missing instead of showing errors.
- More states to test (the fixture matrix) until the PRs are merged; each R task shrinks it again.
- `ServerCapabilities` (ADR 0013) is reshaped: the feature list with states and privilege names is permanent, the
  field/404-based fallbacks are removed per PR. ADR 0013 is marked superseded when the new model lands.
- No Phase 2 write features are added: signing out of a shift is only offered as a link to the web page.
- Details of the plan: `docs/backlog.md` (K-10 – K-13, S-01 – S-06, W-01 – W-05, R-02 – R-13, R-50) and the planned matrix in
  `docs/architecture.md`.
