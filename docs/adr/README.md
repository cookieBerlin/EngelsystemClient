# Architecture Decision Records

Started 2026-10-09. Records significant architectural decisions made
from this point forward — context, the decision itself, and the
consequences/trade-offs accepted. Decisions made before this date are
**not** being retroactively converted; they remain in their original
narrative form in [`../ARCHITECTURE.md`](../ARCHITECTURE.md) and
[`../HISTORY.md`](../HISTORY.md).

## When to write one

Write an ADR when a decision has real trade-offs worth a future session
understanding *why* — not for routine implementation choices that
[`../IMPLEMENTED_FEATURES.md`](../IMPLEMENTED_FEATURES.md) already
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
