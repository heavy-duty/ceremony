# Changelog

The curated history of the ceremony itself. Each release's section is
published verbatim as that release's body (lib/changelog.sh extracts it),
so entries say what changed, cite the issue, and stop.

## Unreleased

- `lib/changelog.sh` + `bin/changelog-assemble` — read the `changelog.d/` fragments, assemble one release section (canonical group order, one shape per repo), and consume exactly what was published (#114).
- BUILDER.md — the handed-off PR is the parked claim's fourth shape, its handoff is its declaration, and shape 2 covers the round awaiting its first verdicts (#109).
- Changelog publication — count entries instead of bytes, refuse dangling grouped headings, and seed grouped re-arms with Added/Changed/Fixed (#98).
- `labels-reconcile` — grant callers private-repo check reads and warn when an entire PR sweep is blind (#95).
- `labels-reconcile` — the bootstrap now retires the six GitHub defaults `LABELS.md` publishes as deleted, tolerating both an already-absent label and a refused delete (#93).
- `issueflow-reconcile` — a triage-authored issue arrival stands down with exit 0 instead of killing the run before the sweep (#91).
- FLEET.md — the assignee's `attention` wake: one role-independent trigger ahead of every per-role list, one acked session per demand; a spec on paper until `duty.sh` polls it (#86).
- `attention` doctrine — define its assignee-owned pickup, ack, queue and clock semantics across labels, triage, and builder roles (#85).
- `attention` — add the issue-only, hand-set assignee-demand flag to the core label taxonomy (#84).
- `issueflow-reconcile` — keep cross-repo references out of local dependency decisions and require triage to resolve cross-repo blockers by hand (#61).
- `needs-ruling` — the cross-cutting flag for a pending human decision, excluded from `state:needs-human` and from the staleness sweep (#51).
- Cross-repo doctrine: the panel is the PR's repo's roster, a review request is authorization but not panel membership, and `Part of <repo>#N` replaces the `Closes #N` that cannot cross repos (#57).
- `actions/runner-isolated` — a `pull_request`-triggered job may never run on a self-hosted runner (#58).
- The sweep's `needs-ruling` invariants, one implementation for both surfaces: the issue-side staleness exemption, the bare-flag check (comment-only, the label is never removed), and the 7-day nudge to the decider (#52).
- `offsite` — protect claimed issues whose PR lives in another repository from the claim-reclaim clock (#68).
- `issueflow-reconcile` — nudge once when an `offsite` flag outlives every visible cross-referenced PR (#69).
- Ruling doctrine — define every human-owned trigger, the fixed escalation shape, and the 0–24h builder-to-triage ladder (#72).
- The sweep observes the escalation contract: a malformed escalation is named field-by-field, and the ladder's 12h/24h rungs each draw one comment to the flag-setter — comment-only, per-episode, both surfaces (#73).
- FLEET.md — the operator notifier's `needs-ruling` queue (one tracked message per item, edited in place across the rungs) and triage's past-24h wake condition; a spec on paper until an operator updates the box (#74).
- One issue at a time counts build work in flight: the parked claim's three shapes, its declared-never-inferred comment, and triage's duty to name a directed hold as a park (#77).

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
