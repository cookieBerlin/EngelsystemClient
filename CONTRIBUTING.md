# Contributing

## Branches

- `main` is always buildable. Small changes may go straight to `main`;
  larger ones use `feat/<topic>`, `fix/<topic>`, `docs/<topic>`.

## Commits

- One logical step per commit. Code, tests and affected documentation go
  into the **same** commit.
- [Conventional Commits](https://www.conventionalcommits.org/) with scope:
  `feat(kit): …`, `fix(ios): …`, `docs(adr): …`. Scopes: `kit`, `ios`,
  `watch`, `complication`, `docs`, `adr`, `build`.
- Reference the backlog item in the body, e.g. `Backlog: D-08`.
- Everything in the repository is English (code, comments, commits, docs,
  UI strings).
- Push when a larger block of work is finished, not after every commit.

## Definition of done

1. Tests added for new logic (Swift Testing in `EngelsystemClientKit`,
   XCUITest for non-trivial UI flows); `swift test` green; new or changed
   code at **100 % line coverage** (`Scripts/check-all-coverage.sh`, ADR 0009/0010).
2. Full Xcode build of the iOS app **and** the Watch app succeeds.
3. User-facing text is English and ready for localization.
4. Documentation updated (see the map in [`CLAUDE.md`](CLAUDE.md));
   [`docs/privacy.md`](docs/privacy.md) updated if data handling changed, and
   [`docs/guide.md`](docs/guide.md)/[`docs/faq.md`](docs/faq.md) if user-visible behavior changed.
5. New decisions with real trade-offs recorded as an ADR in
   [`docs/adr/`](docs/adr/README.md).
6. [`CHANGELOG.md`](CHANGELOG.md) updated under `[Unreleased]` for
   user-visible changes.
7. **Releases:** every TestFlight/App Store upload has a dated `CHANGELOG.md` section and an
   annotated `v<version>` git tag (message = changelog section) on the archived commit, plus a GitHub Release (see [`docs/release.md`](docs/release.md)).
8. No new third-party dependency without an ADR; its license must be
   compatible with GPL-2.0.

## Coding agents

Coding agents follow [`CLAUDE.md`](CLAUDE.md). Finish and commit the
current step before another agent or person edits the same files.

## Issues and pull requests

Issues use the forms in `.github/ISSUE_TEMPLATE/` (bug report, feature request); pull requests the checklist in
`.github/PULL_REQUEST_TEMPLATE.md`. Everyone taking part follows the [Code of Conduct](CODE_OF_CONDUCT.md).

## Security

Vulnerabilities are reported privately, see [`SECURITY.md`](SECURITY.md). 
Never commit API keys, personal paths or private hostnames; see
[`docs/security.md`](docs/security.md).
