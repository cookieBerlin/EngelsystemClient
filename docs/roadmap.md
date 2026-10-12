# Roadmap

Forward-looking planning: features not yet implemented, release
planning, and open decisions awaiting the user's input. Move an item
here as soon as planning firms up past "just an idea" — not just in
chat. Once a planned item is broken into concrete tasks, move those
into [`backlog.md`](backlog.md); once it actually ships, move its entry
into [`features.md`](features.md) with a dated
note and remove it from here.

## In progress

### TestFlight release (started 2026-10-09)

Goal: get the app into TestFlight, both Internal and External testing.

- **Repo visibility**: the GitHub repo (`cookieBerlin/EngelsystemClient`)
  is currently private and will be switched to public by the user
  themselves (not by Claude) before Pages can serve it on the free plan.
- **Security/privacy audit of the full repo + git history**, done
  2026-10-09 ahead of going public — see
  [`history.md`](history.md#2026-10-09-pre-public-security-audit) for
  the full writeup. Result: no real secrets/credentials ever committed.
  Two low-risk informational items found; both resolved the same day —
  the private LAN IP in `CLAUDE.md` was redacted immediately, and the
  old local absolute path in git history was scrubbed via a full
  `git filter-repo --replace-text` rewrite (user-approved — see "Open
  decisions" below for the now-resolved record).
- **LICENSE added 2026-10-09**: GPL-2.0 (user's explicit choice — not
  MIT/Apache-2.0, the two more common defaults for a project like this,
  so noted here rather than assumed). Inserted at the very first commit
  (via `git rebase --root`, same rewrite pass as the history scrub
  above) so the whole project's history is covered by it, not just
  commits from 2026-10-09 onward.
- **Required Apple-facing web pages, hosted via GitHub Pages** (chosen
  over a GitHub Wiki — see [`adr/`](adr/) once that decision gets its
  own ADR, or treat this roadmap entry as the record for now):
  - Privacy Policy — required by App Store Connect before any
    TestFlight build (internal or external) can be distributed.
    Content generated from the app's actual data handling (CloudKit
    sync, Keychain storage, local-only notifications, no analytics/
    tracking, Demo Mode, and — since 2026-10-09 — on-device MetricKit
    crash/diagnostics reporting, see `features.md`'s
    `MetricKitReporter` entry) — not boilerplate. **Must be kept up to
    date whenever data handling changes** — same standing-maintenance
    expectation as `CLAUDE.md` itself.
  - Support page — contact method: GitHub Issues **and**
    `EngelsystemClient@cuccato.net`.
  - Both served from `docs/` on `main` via GitHub Pages (Jekyll
    auto-renders Markdown — no separate build step), default
    `<user>.github.io/<repo>/...` URL, no custom domain.
  - **Content written 2026-10-09**: `docs/privacy.md`, `docs/support.md`,
    `docs/index.md`, and `docs/_config.yml` (theme `jekyll-theme-minimal`,
    excludes the dev-facing docs — `architecture.md`/
    `features.md`/`app-store.md`/`history.md`/
    `roadmap.md`/`backlog.md`/`adr/` — from being published as public
    pages, so CLAUDE.md's existing cross-references into `docs/*.md`
    keep working unchanged). Not yet verified live — needs the repo to
    actually go public and GitHub Pages enabled first (see
    `backlog.md`).
- **Repo public, Pages live, app record created** (2026-10-12): Privacy/
  Support URLs verified (HTTP 200) at `cookieberlin.github.io/EngelsystemClient/`.
  Git history was re-scrubbed and force-pushed first (private LAN IP removed).
- **App Store Connect metadata** — app record exists; still open: Beta
  App Description, Feedback Email, export compliance questions.
- **Internal Testing group** — done 2026-10-12 (build 0.1.0 (2)).
- **External Testing** — submitted for Beta App Review 2026-10-12 (build 0.1.0 (2)); waiting
  for Apple.

### Working with servers that lack the open Engelsystem PRs (planned 2026-10-12)

Goal: the app stays fully usable — and never shows errors for missing features — against Engelsystem servers that do not
have PRs #1709 (no `api` privilege for `/users/self/*`, `/news`), #1710 (`GET /news/{id}`, `comments_count`) and #1711
(`GET /locations/{id}`, no `api` privilege for locations). Owner decisions (2026-10-12): **news comments are optional and
simply not shown when the server lacks them; locations the same — if they cannot be retrieved they are hidden.**

Problems today (see the analysis in the chat of 2026-10-12): `comments_count` is a required field of `News`, so a server
without #1710 breaks the whole News list (decoding error); that failure also makes the app-start/background sync skip
scheduling shift reminders; `/news/{id}` and `/locations/{id}` errors are shown as banners; "Test Connection" can report
success although every data endpoint answers 403.

Design (details in the backlog, items K-01 – K-07):

- **Lenient API model**: `comments_count` becomes optional in our `openapi.yml` copy (a documented local divergence from the
  upstream branch, re-checked after the PRs merge); a missing value counts as "no comments feature".
- **Capabilities instead of errors**: a small *device-local* capability store (not CloudKit-synced, so no CloudKit schema
  change) records per instance whether news comments, the locations list and location detail are available. Filled for free
  from sync results: comments are supported when `/news` items carry `comments_count`; the locations list when `/locations`
  succeeds; location detail when its first refresh succeeds. Anything unavailable is hidden; a 404/403 on these optional
  endpoints is never an error banner. The existing Messages probe keeps its place (`Instance.messagesSupported`).
- **UI**: no "N Comments" link or comments screen without support; the Locations sidebar entry only when at least one active
  instance can list locations; a shift's location is plain text when there is no cached location; the location detail
  screen just shows what is cached (no refresh error).
- **Connection check**: "Test Connection" also probes a real data endpoint; a 403 is reported as a warning "the server denied
  access (403)" in neutral wording (no group names) — Save stays possible (owner decision) — instead of "Connection verified"; the text says the account lacks the `api` privilege and must be added to one of the groups that have it (e.g. "API" or "Bureaucrat").
- **Reminders independent of News**: shift reminders are planned whenever the *shift* sync succeeded, regardless of News,
  Profile or Locations failing.
- **Temporary by design**: every workaround is tagged `COMPAT(#<PR>)`, listed in a register in `docs/architecture.md` and
  removed again by backlog task R-01 once the PRs are closed — afterwards a missing endpoint or a 403 is a real error
  again and the app may assume the servers support everything. The 403 warning names the missing privilege and says the
  account must be added to one of the groups that have it (e.g. "API" or "Bureaucrat"); it never mentions pull requests.
- **Website**: a "Server compatibility" section lists the open PRs (#1709, #1710, #1711), their status and what is unavailable without them (K-08); it is removed or rewritten once they are merged.
- Decision record: ADR 0013 (device-local capabilities, optional fields).

## Open decisions

Awaiting the user's input — nothing below should be assumed/acted on
until answered. _(none currently open)_

## Resolved decisions

Kept for the record, now that these are no longer blocking anything:

1. **Old local absolute path in git history** (an early commit of
   `Scripts/generate-api.sh` hardcoded `/Users/cookie/Documents/
   Projekte/...`, fixed in the current script, which resolves its own
   path at runtime): **rewrite it** — done 2026-10-09 via
   `git filter-repo --replace-text`, combined with the LICENSE-insertion
   rewrite below in one pass. All 83 commit hashes changed again (same
   scope as the 2026-09 German-content rewrite); verified 0 remaining
   occurrences of the real path across all history afterward, and that
   `EngelsystemClientKit` still builds clean post-rewrite.
2. **MetricKit data handling model**: **local + manual export/share** —
   implemented 2026-10-09 as `MetricKitReporter`, see
   `features.md` for the full writeup.
3. **LICENSE**: **GPL-2.0** — added 2026-10-09, the canonical text
   fetched verbatim from `gnu.org` (not reconstructed from memory, to
   avoid any inaccuracy in a legal document) and inserted into the very
   first commit via `git rebase --root`, so it covers the project's
   entire history, not just new commits.
