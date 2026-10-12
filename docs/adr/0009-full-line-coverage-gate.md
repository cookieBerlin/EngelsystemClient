# 0009. 100 % line coverage gate for non-excluded code

- **Status**: Accepted
- **Date**: 2026-10-12

## Context

[ADR 0002](0002-adopt-structured-documentation-layout.md) left out the
100 % coverage gate as "not requested". The owner clarified the same day
that the gate applies to this project as well. A measured baseline on
2026-10-12: `EngelsystemClientKit` own code 76.0 % (23 files below 100 %),
iOS app target 15.5 % from unit tests alone, Watch app and complication
0 %.

## Decision

- **Every source file that is not listed in `Scripts/coverage-exclusions.txt`
  must have 100 % line coverage.**
- Exclusions need a justification comment in that file **and explicit owner
  approval** (date noted). Generated code (`Generated/`, ADR 0003) is
  excluded by construction. Typical other candidates are thin adapters over
  system APIs that tests cannot drive (e.g. MetricKit delivery, Keychain
  access groups); each is proposed to the owner, never added silently.
- `Scripts/check-coverage.sh` runs the `EngelsystemClientKit` tests with
  coverage and fails below the threshold. App and Watch targets are brought
  under the same gate step by step (see `docs/backlog.md`).
- **Ratchet during the ramp-up**: the gate is the target for the whole code
  base, but existing files below 100 % are tracked as backlog items instead
  of blocking unrelated commits. New or changed code must reach 100 % in the
  same commit, and a file that reaches 100 % must not drop below again.

## Consequences

- More tests (especially for `APIClient`'s real-network path and the
  Keychain stores) and more test seams (injectable `URLSession`/store
  doubles) in production code.
- Platform-guarded code (`#if os(iOS)`) is invisible to `swift test` on
  macOS; it needs either an Xcode-based coverage run or a justified
  exclusion.
- `docs/testing.md` documents the workflow; `CONTRIBUTING.md` and
  `CLAUDE.md` state the rule.
