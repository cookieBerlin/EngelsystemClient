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
   [`docs/privacy.md`](docs/privacy.md) updated if data handling changed.
5. New decisions with real trade-offs recorded as an ADR in
   [`docs/adr/`](docs/adr/README.md).
6. [`CHANGELOG.md`](CHANGELOG.md) updated under `[Unreleased]` for
   user-visible changes.
7. No new third-party dependency without an ADR; its license must be
   compatible with GPL-2.0.

## Coding agents

Coding agents follow [`CLAUDE.md`](CLAUDE.md). Finish and commit the
current step before another agent or person edits the same files.

## Security

Never commit API keys, personal paths or private hostnames; see
[`docs/security.md`](docs/security.md).
