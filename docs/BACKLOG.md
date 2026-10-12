# Backlog

Concrete, ready-to-pick-up development tasks — the tactical counterpart
to [`ROADMAP.md`](ROADMAP.md)'s strategic/feature-level planning. An
item moves here once it's broken down enough that someone could
actually start on it; it's removed (not just checked off) once it's
done and reflected in [`IMPLEMENTED_FEATURES.md`](IMPLEMENTED_FEATURES.md).

## TestFlight release

- [ ] Upload a first build (Xcode Archive → App Store Connect), answer
      export compliance (standard HTTPS only → likely exempt).
- [ ] Set up Internal Testing group and upload a build.
- [ ] Prepare for External Testing / Beta App Review (export compliance
      answers, etc.) once Internal Testing is confirmed working.

## Documentation restructure (see ROADMAP.md)

Each item is its own commit; update all cross-references (incl.
`docs/_config.yml` excludes and the memory notes) in the same commit.

- [ ] **D-02** `git mv` docs to lowercase names (`architecture`,
      `features`, `history`, `roadmap`, `backlog`) and fix links,
      `_config.yml` excludes, `CLAUDE.md` map.
- [ ] **D-03** Move tech stack, project structure, API summary and Demo
      mode from `CLAUDE.md` into `docs/architecture.md`.
- [ ] **D-04** Create `docs/requirements.md` from `CLAUDE.md`'s scope
      sections (Phase 1 / Phase 2 rules).
- [ ] **D-05** Create `docs/testing.md` from `CLAUDE.md`'s Testing
      section.
- [ ] **D-06** Rename `ENTITLEMENTS.md` → `docs/app-store.md`; add
      identifiers, privacy and export-compliance notes.
- [ ] **D-07** Create `docs/security.md` and `docs/release.md`.
- [ ] **D-08** Slim `CLAUDE.md` to the rules file: language, work loop,
      commit rules (Conventional Commits, `Backlog: <ID>`), architecture
      rules, constraints, commands.
- [ ] **D-09** Add `CONTRIBUTING.md` and `CHANGELOG.md`; update
      `README.md`'s documentation table.
- [ ] **D-10** Retroactive ADRs 0003ff. for the big earlier decisions
      (list in ROADMAP.md); dates from `docs/history.md`/git log.
- [ ] **D-11** Add backlog IDs to existing items; update the memory note
      on the docs layout.
