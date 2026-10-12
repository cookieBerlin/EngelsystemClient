# 0001. GitHub Pages (not a Wiki) for the Privacy Policy/Support pages Apple requires

- **Status**: Accepted
- **Date**: 2026-10-09

## Context

Submitting to TestFlight (Internal or External testing) requires a
Privacy Policy URL in App Store Connect, and a Support URL is strongly
recommended. The user wanted these pages hosted in the project's own
GitHub repo rather than on a separate hosting provider, but was unsure
whether to use a plain Markdown file (viewed via GitHub's own file
blob view), a GitHub Wiki, or something else — and specifically asked
whether a Wiki's content could be auto-generated from Markdown.

Three options were considered:

1. **A plain `.md` file, viewed via GitHub's blob UI**
   (`github.com/.../blob/main/PRIVACY.md`). Zero setup, but renders
   inside GitHub's own site chrome (sidebar, repo navigation) rather
   than as a clean, standalone page — looks less like a dedicated
   legal page to a reviewer, even though it's a technically valid URL.
2. **A GitHub Wiki.** Lives in a *separate* git repository
   (`<repo>.wiki.git`) from the main repo, with its own history. Can be
   edited via GitHub's web UI or by cloning that separate repo and
   pushing Markdown to it — but nothing keeps it in sync with the main
   repo's own `docs/` folder automatically; that would need a
   dedicated CI job pushing to the second repo, adding real ongoing
   maintenance surface for no corresponding benefit here.
3. **GitHub Pages**, serving directly from the `docs/` folder on
   `main`. GitHub Pages' built-in Jekyll build automatically renders
   Markdown into styled HTML with no separate build step or plugin —
   exactly the "auto-generate a page from Markdown" capability the
   user was asking whether a Wiki could do, except Pages already does
   it without needing a second repo at all.

## Decision

Use **GitHub Pages**, source `main` branch / `/docs` folder, default
`jekyll-theme-minimal` theme, default `<user>.github.io/<repo>/...`
URL (no custom domain). `docs/_config.yml`'s `exclude:` list keeps the
project's own internal documentation (`architecture.md`,
`features.md`, `ENTITLEMENTS.md`, `history.md`,
`roadmap.md`, `backlog.md`, `adr/`) out of the published site, so only
`privacy.md`/`support.md`/`index.md` actually become public pages.

## Consequences

- One repo, one history, one source of truth — `docs/privacy.md` is
  both the file a future session edits via `CLAUDE.md`'s documentation
  map *and* the file Pages publishes, with no separate sync step that
  could drift or be forgotten.
- Requires the repo to be public (or a paid GitHub plan) for Pages to
  actually serve — acceptable here since the repo is being made public
  anyway as part of this same release.
- `docs/_config.yml`'s `exclude:` list is easy to forget about if a
  new top-level file is ever added to `docs/` that *shouldn't* be
  public — worth double-checking against this list when adding
  anything there, not just assuming `docs/` is uniformly internal or
  uniformly public.
- The Wiki option is not used at all — if a future need specifically
  wants Wiki-style collaborative editing (e.g. from non-maintainers
  without repo write access), that would be a new decision, not a
  natural extension of this one.
