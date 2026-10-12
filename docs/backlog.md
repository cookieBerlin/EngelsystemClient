# Backlog

Concrete, ready-to-pick-up development tasks (IDs like `T-01`; reference them as
`Backlog: T-01` in commit bodies) — the tactical counterpart
to [`roadmap.md`](roadmap.md)'s strategic/feature-level planning. An
item moves here once it's broken down enough that someone could
actually start on it; it's removed (not just checked off) once it's
done and reflected in [`features.md`](features.md).

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
      **The published website already assumes this state** (no group requirement is mentioned), so only the internal
      docs and the app lag behind until then.

_(No other open tasks. TestFlight: build 0.1.0 (2) is in internal testing and submitted for
Beta App Review as of 2026-10-12; if Apple rejects it, the owner reports the reason here.)_
