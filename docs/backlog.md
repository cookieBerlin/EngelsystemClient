# Backlog

Concrete, ready-to-pick-up development tasks (IDs like `T-01`; reference them as
`Backlog: T-01` in commit bodies) — the tactical counterpart
to [`roadmap.md`](roadmap.md)'s strategic/feature-level planning. An
item moves here once it's broken down enough that someone could
actually start on it; it's removed (not just checked off) once it's
done and reflected in [`features.md`](features.md).

## TestFlight release

- [ ] **T-02** Internal Testing (owner, in App Store Connect): wait until build 0.1.0 (2) shows
      "Ready to Test" under TestFlight → Builds; create an *Internal* group (e.g. "Team"), add
      yourself (App Store Connect users only), assign the build, install it via the TestFlight
      app on iPhone and Watch, and smoke-test: Demo Mode, a real instance, notifications,
      complication, Settings > Export Diagnostics. Answer the build's compliance prompt only if
      shown (the Info.plist pre-answers it).
- [ ] **T-03** External Testing / Beta App Review (owner, then Claude drafts texts): under
      TestFlight > Test Information fill in Beta App Description, Feedback Email
      (`EngelsystemClient@cuccato.net`), Privacy Policy URL
      (`https://cookieberlin.github.io/EngelsystemClient/privacy`) and, for review, a note that
      reviewers need no account: use **Try Demo Mode** on the first screen. Then create an
      *External* group and submit the build for Beta App Review. Draft texts: see `release.md`.
