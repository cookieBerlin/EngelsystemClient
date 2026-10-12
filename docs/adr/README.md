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
`NNNN-short-kebab-case-title.md`. Each uses this template:

```markdown
# NNNN. Title

- **Status**: Proposed | Accepted | Superseded by NNNN
- **Date**: YYYY-MM-DD

## Context

What problem or question forced this decision. The constraints in play.

## Decision

What was decided, stated plainly.

## Consequences

What this makes easier, what it makes harder, and any trade-offs
knowingly accepted. Link onward (`docs/IMPLEMENTED_FEATURES.md`, other
ADRs) rather than duplicating detail that lives there.
```

A superseded ADR is **not** deleted or edited to reflect the new
decision — add a new ADR, and change the old one's `Status` line to
point at it, so the history of *why things changed* stays readable.

## Index

_(none yet)_
