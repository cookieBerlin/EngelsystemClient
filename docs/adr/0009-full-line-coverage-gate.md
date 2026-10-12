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
- **Standing approval (owner, 2026-10-12): thin adapter layers over system
  APIs may always be added to the exclusion list** (no per-file request
  needed), provided all decision logic lives behind a protocol/closure seam
  in a separately tested file and the adapter itself is a few lines with a
  justification comment. Anything that is not such an adapter still needs
  explicit approval.
- `Scripts/check-coverage.sh` (Kit), `Scripts/check-app-coverage.sh` (iOS and
  Watch app, from an Xcode coverage run) and `Scripts/check-all-coverage.sh`
  (all three) fail below the threshold.
- **Ramp-up finished 2026-10-12**: `EngelsystemClientKit`, the iOS app and the
  Watch app all pass (`Scripts/check-all-coverage.sh`). From now on the gate is
  blocking: no commit may leave any target below 100 % (new or changed code
  needs its tests in the same commit).

## Consequences

- More tests (especially for `APIClient`'s real-network path and the
  Keychain stores) and more test seams (injectable `URLSession`/store
  doubles) in production code.
- Platform-guarded code (`#if os(iOS)`) is invisible to `swift test` on
  macOS; it needs either an Xcode-based coverage run or a justified
  exclusion.
- `docs/testing.md` documents the workflow; `CONTRIBUTING.md` and
  `CLAUDE.md` state the rule.
