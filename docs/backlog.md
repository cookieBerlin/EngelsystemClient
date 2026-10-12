# Backlog

Concrete, ready-to-pick-up development tasks (IDs like `T-01`; reference them as
`Backlog: T-01` in commit bodies) — the tactical counterpart
to [`roadmap.md`](roadmap.md)'s strategic/feature-level planning. An
item moves here once it's broken down enough that someone could
actually start on it; it's removed (not just checked off) once it's
done and reflected in [`features.md`](features.md).

_(No open tasks. TestFlight: build 0.1.0 (2) is in internal testing and submitted for
Beta App Review as of 2026-10-12; if Apple rejects it, the owner reports the reason here.)_

## App Store screenshots (see ROADMAP.md)

- [ ] **S-03** `Scripts/screenshots.sh` for iPhone: simulator prep, test run, attachment export (names come from
      `suggestedHumanReadableName` in `manifest.json`, prefix before `_0_`), pixel-size check, EXIF strip, status bar override
      (9:41 — the test itself does not set it). A fresh simulator is slow for a while (Apple's own widget renderer
      compiles shaders and may crash with a watchdog report — harmless); one run took ~5 minutes, so keep generous timeouts.
- [ ] **S-04** iPad (landscape) support in the script and tests.
- [ ] **S-05** Apple Watch screenshot via the seed argument and `simctl io`.
- [ ] **S-06** Docs (`app-store.md`, `release.md`, `.gitignore`) and the ADR.
- [ ] **S-07** Full run on all devices; review every image; fix scene issues.
