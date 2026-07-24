# Changelog

The curated history of the ceremony itself. Each release's section is
published verbatim as that release's body (lib/changelog.sh extracts it),
so entries say what changed, cite the issue, and stop. Entries arrive as
fragments — one `changelog.d/<issue>.md` per PR, never an edit to this
file — and the release PR assembles them into the next section here
(`bin/changelog-assemble`, #112). Each entry is at most 300 characters after
wrapped lines are joined and whitespace is collapsed; a genuinely long
change ships as several short `- ` entries in the same fragment, never one
long entry.

## 0.3.0 — 2026-07-24

- Make `changelog-armed` reject fragment shape drift on the PR that introduces it.
- A directive hold now has a written ending, not just a beginning: BUILDER.md's shape 5 says the hold ends where it began — on the labels — with the hold owner's most recent queue-label event governing over any stale prose, the timeline read (`gh api .../issues/{n}/timeline`) named as the move before standing down or up on a hold, a claim against stale prose required to cite the events it read, and a refused claim given its two exits. TRIAGE.md now requires re-reading label events before asserting label-borne state in prose, and makes correcting a lifted hold's stale body header triage's move in the same tick. On 2026-07-24 the unranked signals split two builders reading one board (#149, #151); both acted defensibly — the doctrine, not the builders, lacked the rule (#154).
- Doctrine names the second `Closes #N` exception: a same-repo PR whose
  authorizing issue marks an acceptance criterion post-merge uses `Refs #N`,
  and triage closes the issue by hand on the evidence — merging #143
  auto-closed #137 with exactly such a criterion unmet, and no role had been
  told otherwise. TRIAGE.md now requires a post-merge criterion to carry its
  own mechanism (post-merge, triage closes, `Refs #N`), REVIEWER.md lists
  `Refs #N` beside `Closes #N` and `Part of <owner>/<repo>#N` and stops
  treating the reference-only PR as a defect, and CONTRIBUTING.md points at
  BUILDER.md as the rule's one home (#151).
- FLEET.md — the Reviewers wake describes the deployed sweep, not the `gh search` trigger the bench replaced: the pulls-API `requested_reviewers` sweep across the org plus the named bot forks is source 1, the `repos.txt`/search poll an adds-only backstop, and the two are merged and deduplicated by (repo, PR) before acting. Only the notifier's `needs-ruling` queue remains on paper; `repos.txt` is the registry only on the triage box; and the Status block now stamps the crew ref the file was last reconciled against (#149).
- REVIEWER.md now carries the review mechanics every box had been re-deriving from an incident: the queue comes from the API and not the search index, every write is one-shot per (reviewer, PR, head), heads are reviewed in throwaway checkouts, a pinned consumer's config is verified at its pin, and a verdict names the checks its box could not run (#145).
- The `docs/CONSUMERS.md` labels-caller stub lists the same `issues:` types
  as ceremony's own caller — `edited` and `reopened` included — so a consumer
  adopting the stub wakes when an issue body's `Blocked by #N` declaration is
  edited, and when a closed issue re-enters the queue wearing labels derived
  at close. The two lists drifted apart inside PR #32; a parity test now pins
  them together, red if either file drops a type or the lists diverge.
  Adopting the widened list is a stub edit riding the pin bump to the first
  tag carrying this change (#144).
- `labels-reconcile` — a queue-cancelled duplicate check is discarded when its context holds a real verdict, so a sibling PR's eviction no longer reds a green PR; an all-cancelled context still blocks (#139).
- `blocker:unrequested` now clears the moment the panel is asked: the labels
  caller (and the `docs/CONSUMERS.md` stub) listens on `review_requested` and
  `review_request_removed`, so the one event that falsifies the label — or
  makes it true again — wakes the reconcile sweep instead of waiting for an
  unrelated push or the advisory cron. The `scope` job skips both events:
  they change no paths, and running the labeler on them widens the #130
  clobber window. Adopting the new triggers is a stub edit riding the pin
  bump to the first tag carrying this change (#137).
- `drills/README.md` no longer tells the builder to delete the scratch repo —
  a step no fleet identity can perform, because `delete_repo` is deliberately
  absent from bot tokens. The builder's end state is **archive**
  (`archived: true`, inside the `repo` scope); the delete is the operator's,
  and cleanup gates nothing — not ready-for-review, not the panel, not the
  merge. The drill record now names the scratch repo by `owner/name` and
  states the disposal its author actually observed, never one that has not
  happened: both 0.2.0 drills hit the missing-scope wall independently, one
  stalling a release draft on an impossible 403, the other shipping a record
  asserting a delete that never ran (#135).
- `lib/facts.sh` — a repository's first push to `main` (a root commit with no first parent) now reads `base_ver=(none)` and lets decide's table govern, instead of dying at exit 128 before establishing a fact; the no-base path skips the base fetch and `git show`, and an unresolvable head still fails loudly (#134).
- The changelog rule now explains why release PRs write no fragment and how entry-worthy changes land instead (#131).
- `actions/labels-scope` replaces `actions/labeler@v5` in the labels workflow's scope job: labeler wrote the whole label set (`PUT`) even under `sync-labels: false`, silently removing any label applied while it ran — #128 lost its `release` that way — so the scope job now derives from the same `.github/labeler.yml` mapping (the `changed-files`/`any-glob-to-any-file` shape, block or flow; anything else refuses loudly) and its only write is an additive `POST`. The reconcile sweep also warns — never sets — when a non-draft PR is release-shaped (bare version differing from its base) but carries no `release` label (#130).

## 0.2.0 — 2026-07-24

- `test/changelog-assembled.test.sh` — keep the trio interaction aligned with fragment mode: a dropped entry makes armed red too, while a hand-edited section leaves assembled as the sole red (#126).
- `actions/changelog-assembled` — a release PR's stamped section must be byte-for-byte what the fragments it consumed assemble to, replayed from the merge base; inapplicable trees pass with a NOTICE (#116).
- `changelog-armed` — treat `changelog.d/` as the arming, validate every development fragment, and require bare releases to consume the directory into their exact publishable section (#115).
- `lib/changelog.sh` + `bin/changelog-assemble` — read the `changelog.d/` fragments, assemble one release section (canonical group order, one shape per repo), and consume exactly what was published (#114).
- BUILDER.md — the directed hold is the parked claim's fifth shape, its attention demand is acknowledged in the declaration comment, and its board bookkeeping covers in-flight work; TRIAGE.md no longer excludes it (#113).
- Ceremony adopts `changelog.d/` — a PR writes one fragment per issue instead of editing `CHANGELOG.md`, the release PR assembles the section, and `## Unreleased` is gone (#112).
- BUILDER.md — the handed-off PR is the parked claim's fourth shape, its handoff is its declaration, and shape 2 covers the round awaiting its first verdicts (#109).
- `labels-reconcile` — warn once per sweep when a repository lacks labels declared by the pinned core taxonomy (#105).
- `LABELS.md` — drop the vendored scope-table enumeration; the per-repo set lives in `.github/labels.conf` and the repo's own CONTRIBUTING (#104).
- `labels-reconcile` — a degraded mergeability/checks read now logs gh's actual stderr (collapsed, bounded) beside the byte-identical counted line, and the blind-sweep warning leads with the observed reason instead of asserting the permissions cause (#101).
- Changelog publication — count entries instead of bytes, refuse dangling grouped headings, and seed grouped re-arms with Added/Changed/Fixed (#98).
- `labels-reconcile` — grant callers private-repo check reads and warn when an entire PR sweep is blind (#95).
- `labels-reconcile` — the bootstrap now retires the six GitHub defaults `LABELS.md` publishes as deleted, tolerating both an already-absent label and a refused delete (#93).
- `issueflow-reconcile` — a triage-authored issue arrival stands down with exit 0 instead of killing the run before the sweep (#91).
- FLEET.md — the assignee's `attention` wake: one role-independent trigger ahead of every per-role list, one acked session per demand; a spec on paper until `duty.sh` polls it (#86).
- `attention` doctrine — define its assignee-owned pickup, ack, queue and clock semantics across labels, triage, and builder roles (#85).
- `attention` — add the issue-only, hand-set assignee-demand flag to the core label taxonomy (#84).
- One issue at a time counts build work in flight: the parked claim's three shapes, its declared-never-inferred comment, and triage's duty to name a directed hold as a park (#77).
- FLEET.md — the operator notifier's `needs-ruling` queue (one tracked message per item, edited in place across the rungs) and triage's past-24h wake condition; a spec on paper until an operator updates the box (#74).
- The sweep observes the escalation contract: a malformed escalation is named field-by-field, and the ladder's 12h/24h rungs each draw one comment to the flag-setter — comment-only, per-episode, both surfaces (#73).
- Ruling doctrine — define every human-owned trigger, the fixed escalation shape, and the 0–24h builder-to-triage ladder (#72).
- `issueflow-reconcile` — nudge once when an `offsite` flag outlives every visible cross-referenced PR (#69).
- `offsite` — protect claimed issues whose PR lives in another repository from the claim-reclaim clock (#68).
- `issueflow-reconcile` — keep cross-repo references out of local dependency decisions and require triage to resolve cross-repo blockers by hand (#61).
- `actions/runner-isolated` — a `pull_request`-triggered job may never run on a self-hosted runner (#58).
- Cross-repo doctrine: the panel is the PR's repo's roster, a review request is authorization but not panel membership, and `Part of <repo>#N` replaces the `Closes #N` that cannot cross repos (#57).
- The sweep's `needs-ruling` invariants, one implementation for both surfaces: the issue-side staleness exemption, the bare-flag check (comment-only, the label is never removed), and the 7-day nudge to the decider (#52).
- `needs-ruling` — the cross-cutting flag for a pending human decision, excluded from `state:needs-human` and from the staleness sweep (#51).

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
