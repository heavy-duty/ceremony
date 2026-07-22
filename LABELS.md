# Labels

The taxonomy shared across the heavy-duty repos. Only the `scope:` set
differs per repo (each repo's `.github/labels.conf` names its actual
surfaces); everything else below is core and identical everywhere, created by
the labels workflow's bootstrap dispatch (issue #10).

Two state machines share the taxonomy: the **PR machine** (proven in
box/rig/cast, reconciled by machinery) and the **issue flow** (the
triage → build queue, reconciled by the work-queue sweep). One rule joins
everything: **states are machine-owned, intent
labels are hand-set** — a hand-moved state label is a lie waiting to happen,
and the reconciler recomputes it from GitHub's own facts.

## PR state — who is the ball with? (exactly one per open PR)

| Label | Color | Waiting on |
|---|---|---|
| `state:building` | `#FBCA04` | the builder — PR is a draft |
| `state:bots-reviewing` | `#1D76DB` | the reviewer panel to finish the round (a request is live) |
| `state:addressing` | `#D93F0B` | the builder — round complete without full approval, or nobody was asked, or a blocker is up, or a ruling is pending |
| `state:needs-human` | `#8250DF` | the human — **this PR could be merged right now**: zero blockers, whole panel approved the current head |

`bots-reviewing` vs `addressing` is deliberate: staleness in the first means
*poke the reviewers*, in the second *the builder dropped the ball*. And
`state:needs-human` means exactly one thing — a human could merge this now —
so it requires zero blockers and head-current approvals; anything less and
the reconciler takes it back. The author sets it at handoff (the one
hand-set state); the `labeled` event fires the sweep that validates the
write within seconds.

## PR blockers — what is in the way? (facts, as many as apply)

| Label | Color | Means |
|---|---|---|
| `blocker:conflict` | `#B60205` | does not merge — the builder owes a **rebase** |
| `blocker:ci-red` | `#B60205` | a check failed — the builder owes a **fix**, which a rebase will not provide |
| `blocker:unrequested` | `#E99695` | this head has no verdict from somebody, and nobody was asked |
| `blocker:drill-pending` | `#B60205` | a `release` PR whose version has no `drills/X.Y.Z.md` record — correct but unevidenced (maintainer-created label; the bot bootstrap 403s on it) |

States answer *whose ball*; blockers answer *what's in the way*. They are
separate axes because the single-label version kept lying — independent facts
projected onto one totally-ordered label meant one always won and the losers
vanished off the board (box's `state:needs-rebase`, retired: the reconciler
strips it on sight).

## Issue flow — the work queue (exactly one per open, triaged, non-epic issue)

| Label | Color | Means | Set by |
|---|---|---|---|
| `needs-triage` | `#FBCA04` | an issue that did not come through triage — it owes normalization or conversion back to a discussion | anyone who spots one; cleared by triage |
| `ready` | `#0E8A16` | triaged, spec complete, unblocked — a builder can start now and succeed | triage |
| `claimed` | `#1D76DB` | a builder owns it: assignee set, a draft PR expected shortly | the claiming builder |
| `blocked` | `#6A737D` | waiting on another issue or PR (`Blocked by #N` in the body names it) | triage; anyone may correct it |
| `epic` | `#5319E7` | organizes other issues via a dependency-ordered task list; **builders never pick an epic** | triage |

The work-queue sweep enforces the invariant a board scan relies on: every open issue is either
`needs-triage`, `epic`, or carries exactly one of `ready` / `claimed` /
`blocked`. It flags conflicts rather than guessing intent. A `claimed` issue
with no open PR and no activity for 48 hours is reclaimed by the sweep: it
comments, unassigns the stale owner, and restores `ready`.

## Cross-cutting (PRs and issues)

| Label | Color | Meaning |
|---|---|---|
| `stale` | `#B60205` | no activity for 48h — sweep-managed, never hand-applied |
| `blocked` | `#6A737D` | (see above — same label serves PRs waiting on another PR/issue; legitimately quiet, the staleness sweep skips it) |
| `needs-ruling` | `#D4C5F9` | a human decision is required; the question, options and a recommendation are in the flagging comment. Set by triage or the builder; a state, not a signal — it clears on agreement, not on a reply |
| `release` | `#0E8A16` | release flow, versioning, packaging work — and the ceremony PR itself |
| `merge-next` | `#0E8A16` | head of the merge queue — merge this one next. Queue order is *intent*: never set by the reconciler, only cleared by it |

`needs-ruling` marks where the human's turn is when the pending thing is a
*decision*, not a merge (#50 settled it, D1–D10). It is not
`state:needs-human`: that label means exactly "this PR could be merged right
now", and the retired `state:needs-rebase` is the family's proof that a
label meaning two things lies about both. It is not a `blocker:*` either:
every blocker names work the *builder* owes, a ruling is owed by the human —
and the flag must live on issues too, where blockers do not exist. On issues
it coexists with the queue labels (the one-of-three invariant above ignores
it); its color is the light shade of `state:needs-human`'s, so the human
axis reads as one family. It is a state, not a signal: set only with the
escalation contract (the question, the options, a recommendation — a bare
flag is noise), it stays up until agreement is *reached* — a human reply
alone does not clear it — and its setter closes it out: records the ruling
as a decision in one comment, removes the label, and returns the item to
its flow in that same comment, never as a side effect. If the human
disagrees that agreement was reached, the label goes back on. The machine
reads it and never writes it: the reconciler refuses `state:needs-human`
while it stands (the PR falls to `state:addressing` — the ball on the PR is
the builder's, who carries the ruling in), and the staleness sweep skips
it, because waiting on a human is legitimately quiet.

## Scope — which surface? (PRs and issues, any number)

All scopes share one calm color, `#C5DEF5` — scopes locate, states alert. The
set is per-repo (`.github/labels.conf`); PRs get theirs from changed paths via
actions/labeler, issues get theirs from triage. This repo's set:

| Label | Covers |
|---|---|
| `scope:release-flow` | the reusable release workflow, decide, the doors |
| `scope:guards` | changelog-armed / changelog-monotonic / drill-recorded |
| `scope:labels` | the labels workflow, reconciler, this taxonomy |
| `scope:docs` | README doctrine, CONSUMERS.md, the role files |

## Issue types

`bug`, `enhancement`, `documentation` — issues only, set by triage. PRs carry
their type in the conventional title (`feat:`, `fix:`, `docs:`); a type label
on a PR would say the same thing twice and drift.

## Maintenance

The labels workflow (issue #10) recomputes PR state statelessly on PR events
plus a 15-minute advisory cron, and bootstraps this taxonomy idempotently on
manual dispatch. The same workflow reconciles issue-flow labels on issue
events and during the scheduled sweep. Default GitHub labels (`duplicate`, `invalid`,
`question`, `wontfix`, `help wanted`, `good first issue`) are deleted at
bootstrap — a `question` is a discussion, not an issue.
