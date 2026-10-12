# Architecture Decision Records

Started 2026-10-09. Records significant architectural decisions made
from this point forward — context, the decision itself, and the
consequences/trade-offs accepted. Decisions made before this date were
recorded retroactively (0003–0008, 2026-10-12) as short summaries that
link to the original narrative in [`../architecture.md`](../architecture.md)
and [`../history.md`](../history.md), which stay as written.

## When to write one

Write an ADR when a decision has real trade-offs worth a future session
understanding *why* — not for routine implementation choices that
[`../features.md`](../features.md) already
documents fine on its own. Rule of thumb: if reversing the decision
later would require re-deriving the reasoning from scratch, it belongs
here.

## Format

One file per decision, numbered sequentially:
`NNNN-short-kebab-case-title.md`. Copy [`template.md`](template.md).

A superseded ADR is **not** deleted or edited to reflect the new
decision — add a new ADR, and change the old one's `Status` line to
point at it, so the history of *why things changed* stays readable.

## Index

| ADR | Title | Status |
|-----|-------|--------|
| [0001](0001-github-pages-over-wiki-for-legal-pages.md) | GitHub Pages (not a Wiki) for the Privacy Policy/Support pages | Accepted |
| [0002](0002-adopt-structured-documentation-layout.md) | Adopt a structured documentation layout and working rules | Accepted |
| [0003](0003-generated-dtos-from-openapi.md) | DTOs generated from the OpenAPI spec, never hand-written | Accepted |
| [0004](0004-swiftdata-cloudkit-for-instance-metadata-only.md) | SwiftData with CloudKit for `Instance` metadata only | Accepted |
| [0005](0005-watch-standalone-watchconnectivity-as-nudge.md) | Watch app is standalone; WatchConnectivity only as an optional nudge | Accepted |
| [0006](0006-messages-live-only-with-capability-probe.md) | Messages are live-only and gated by a runtime capability probe | Accepted |
| [0007](0007-demo-mode-via-sentinel-url.md) | Demo mode through a sentinel base URL inside `APIClient` | Accepted |
| [0008](0008-local-notifications-only.md) | Shift reminders as local notifications only | Accepted |
| [0009](0009-full-line-coverage-gate.md) | 100 % line coverage gate for non-excluded code | Accepted |
