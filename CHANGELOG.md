# Changelog

The curated history of the ceremony itself. Each release's section is
published verbatim as that release's body (lib/changelog.sh extracts it),
so entries say what changed, cite the issue, and stop.

## Unreleased

- `needs-ruling` — the cross-cutting flag for a pending human decision, excluded from `state:needs-human` and from the staleness sweep (#51).
- Cross-repo doctrine: the panel is the PR's repo's roster, a review request is authorization but not panel membership, and `Part of <repo>#N` replaces the `Closes #N` that cannot cross repos (#57).

## 0.1.0 — 2026-07-22

- `lib/version.sh` — one version abstraction, `file` and `package-json` backends (#3).
- `lib/changelog.sh` + `bin/changelog-section` — the one canonical changelog-section extractor (#4).
- `actions/changelog-armed` — the version-keyed arming guard (#5).
- `actions/changelog-monotonic` — shipped release headings are append-only: no deletion, no duplication (#6).
- `actions/drill-recorded` — a release tree must carry its drill record (#7).
- `lib/decide.sh` — the merge door's five-state decision, pure and exhaustively tested (#8).
- `.github/workflows/release.yml` + `lib/facts.sh` — the reusable two-door release workflow (#9).
- `.github/workflows/labels.yml` + `actions/labels-reconcile` — label taxonomy bootstrap and PR-state reconciliation (#10).
- Ceremony adopts its own ceremony: `VERSION`, this changelog, the drill doctrine, the self-callers, and the self-guards in CI (#11).
