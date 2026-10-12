# 0002. Adopt a structured documentation layout and working rules

- **Status**: Accepted (the coverage-gate exclusion below was reversed by [ADR 0009](0009-full-line-coverage-gate.md))
- **Date**: 2026-10-12

## Context

`CLAUDE.md` had grown into a mix of rules, API description, tech stack
and testing notes. The owner prefers a different layout: a short,
rules-only `CLAUDE.md`, one lowercase file per topic under `docs/`, a
complete ADR set, `CONTRIBUTING.md`, `CHANGELOG.md` and an ID-based
backlog. Using one layout across projects avoids re-learning
conventions per project.

## Decision

Adopt that layout and its working rules (Conventional Commits with
`Backlog: <ID>`, work loop, CONTRIBUTING, CHANGELOG), lowercase `docs/`
file names, and retroactive ADRs for the major earlier decisions. Not
adopted: a 100 % coverage gate, swift-format lint and test wrapper
scripts (a much larger effort, not requested). Also not carried over:
anything specific to closed-source projects — this one is GPL-2.0.

## Consequences

- A consistent layout across the owner's projects; `CLAUDE.md` stays
  small.
- One-off migration cost and many renamed links; tracked as D-01–D-11 in
  the backlog.
- `docs/_config.yml` excludes must follow every rename, or internal docs
  become public Pages.
- Old narrative decisions in `architecture`/`history` stay as written;
  the new ADRs summarize and link to them rather than rewriting them.
