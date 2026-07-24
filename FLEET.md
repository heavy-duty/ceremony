# FLEET.md — the roster, and how it actually runs

> **Status:** descriptive snapshot, not doctrine. This file records how the
> agent fleet that builds this repo is wired *today*, so the setup can later be
> solidified into a replicable fleet-management solution. It is **not** part of
> the vendored doctrine set (`.ceremony/`) and is never mirrored to consumer
> repos. The doctrine files (AGENTS.md, TRIAGE.md, BUILDER.md, REVIEWER.md,
> LABELS.md, CONTRIBUTING.md) say what roles *must* do; this file says how the
> current bench *physically* does it. Last reconciled against the deployed
> duty scripts at
> [`heavy-duty/crew@b2fd864`](https://github.com/heavy-duty/crew/tree/b2fd8642e7f7aa8dc9de6b44edadbe1dc557b140)
> (private to the org; the fleet can read it), 2026-07-24 — a descriptive
> file with no reconciliation stamp gives the next reader nothing to diff,
> which is exactly how the #149 drift went unnoticed.

## The roster

One box (an isolated, disposable VM) per GitHub identity. Boxes are credential
boundaries; sessions inside a box are role boundaries. No box has an inbound
network path — GitHub is the only queue.

| Identity | Box | CLI | Roles |
|---|---|---|---|
| `dan-claude-bot` | triage-box | Claude Code | **triage** — the only issue-minter |
| `claude-bot-andresmgsl` | claude-box | Claude Code | builder (hard machinery) + reviewer |
| `codex-bot-andresmgsl` | codex-box | Codex CLI | builder (mechanical) + reviewer |
| `grok-bot-andresmgsl` | grok-box | Grok CLI | reviewer |
| `kimi-bot-andresmgsl` | kimi-box | Kimi CLI | reviewer |

Review panel per PR = the reviewer bench minus the PR's author (recusal by
construction). Only humans merge — enforced as permissions (the agents team
holds the triage role, not write), not as convention.

## Anatomy of a duty loop

Every box runs the same skeleton, adapted to its CLI:

- **Tick:** cron `*/5` runs `~/duty/duty.sh` under a non-blocking `flock`; the
  triage box adds an hourly hygiene sweep under its own lock. Holding the lock
  is load-bearing: a tick that acquires it *knows* nothing else is running on
  this identity.
- **Poll:** the script reads `~/duty/repos.txt` and queries GitHub with `gh`
  for work matching the box's role. Whose registry that file is depends on
  the role: the triage box's `repos.txt` **is** its registry — adding a repo
  is adding a line — while a reviewer's registry is the org itself, and its
  `repos.txt` is a backstop that cannot scope it (grok's copy says so in its
  own first line).
- **Act:** when there is work, the script launches the box's CLI as a one-shot
  session with a role prompt; the session does the work via `gh` as the box's
  own identity, then exits. Sessions are stateless and disposable — all state
  lives on the board (issues, PRs, labels) and in git branches.

### Wake conditions

One wake is shared by all three roles, so it is stated once instead of pasted
into each list: **an open issue assigned to me carrying `attention`.** Anyone
can be an assignee, which is why the trigger is role-independent — triage,
builders and reviewers all carry it, and the pickup session is the same shape
in each. It runs **first, ahead of everything in the per-role lists below** —
for builders, ahead of resume: a demand parked by triage, the operator or a
sibling agent outranks self-directed continuation, and it is frequently the
very thing that unparks the work resume would otherwise pick up. The query is
the authenticated-user endpoint —
`gh api "/issues?filter=assigned&state=open&labels=attention"` — one call, no
search index (the reviewer trigger below already records that the index
lags), and like the review-request trigger it reaches repos `~/duty/repos.txt`
does not name.

Each demand gets **exactly one session, and the ack bounds it**: the
session's first act, before any of the demanded work, is the pickup comment
plus removing the label — [the `attention`
contract's](https://github.com/heavy-duty/ceremony/blob/bce09aa7648dbd74b8e91b1d4fbc2fa8d145f705/LABELS.md#L143-L149)
ack (#85), which here becomes the session's ack-then-act ordering.
Then it acts on the thread and exits — short by construction. Until the label
is removed the flag is still up, so a session that dies before acking is
simply relaunched at the next tick; that is the whole crash-recovery story,
and it is the same crash-only shape as resume below.

The design this replaces was built and rejected: polling notifications for
`reason: mention` re-arms a thread on every comment, so ordinary round
traffic — verdicts naming the builder, the builder's own replies echoing back
— burns a full agent session per tick on nothing actionable; a mention
answers *"was I named?"*, not *"am I needed?"*. The incident that bought the
wake: [#16's 16:49Z
ruling](https://github.com/heavy-duty/ceremony/issues/16#issuecomment-5061051198)
authorized the last open acceptance criterion on a `claimed` issue and sat
unowned for over an hour — the box answered every state signal that day and
never saw the comment, and the eventual pickup ran on a manual bridge. Like
the notifier's queue below, this wake is the spec for a box-side change only
the operator can make; until `duty.sh` polls it, the wake exists on paper —
though one consumer already polls for the label and no-ops while it is
absent, so the wiring can be verified live the day the row lands.

- **Triage:** new discussions to mint from, builder questions on issues, stray
  issues to reconcile, `@`-mentions, hourly hygiene (stale claims, label
  invariants), and a `needs-ruling` standing **past 24h** — the ladder's last
  rung makes the option triage's to pick, and this wake list is where triage
  learns such an item exists (see the notifier section below).
- **Builders**, in priority order: **resume** (an open draft PR of mine, or a
  claimed issue with my `build/*` branch but no PR — possible only if a
  previous session died mid-work), a `ready` issue to claim, a completed
  review round on my PR (act on whole rounds, never single verdicts), my PR
  fully approved (write the closing summary, flip to `state:needs-human`,
  request the human), my PR `CONFLICTING` (rebase; never act on `UNKNOWN` —
  post-merge flap).
- **Reviewers**, one candidate set from two merged sources. Source 1,
  authoritative: every open PR in the `heavy-duty` org **plus the named bot
  forks** that lists me in `requested_reviewers`, enumerated straight from
  the pulls API — never `gh search`, whose index lags (cast#143,
  incubator#25 and box#164 each sat unreviewed behind it). A review request
  is authorization, so no repo filter may gate it. Source 2, backstop: the
  `repos.txt` poll for an open PR by someone else whose head I have not yet
  reviewed — it only **adds** candidates the sweep may have missed (an
  org-enumeration failure, say) and never concludes "nothing to do". The
  sources are merged and deduplicated by (repo, PR) **before** acting, not
  run as sequential passes — the sequential shape double-announced on
  ceremony#32, when the request sweep and the repo-list poll each acted on
  the same PR in one tick (operator protocol 2026-07-23) — and worked
  oldest-first. Unchanged: one verdict per head, deduplicated against my
  own latest review's SHA.

#### The operator notifier — the `needs-ruling` queue

The operator notifier (`notify.sh`, on the triage box) watches open PRs
carrying `state:needs-human`. That poll never reads `needs-ruling`, which
lives mostly on *issues* — so an escalation waits invisibly on the very human
it names. Not hypothetical: on 2026-07-23 alone, three escalations spent
their whole lives outside the operator's view — [#16's fork-PR-workflows
question](https://github.com/heavy-duty/ceremony/issues/16#issuecomment-5053302689)
(raised 01:23Z, [ruled 09:24Z](https://github.com/heavy-duty/ceremony/issues/16#issuecomment-5056705884)
— eight hours in which the board showed a `claimed` issue indistinguishable
from a builder mid-build), [#56's R1–R3
escalation](https://github.com/heavy-duty/ceremony/issues/56#issuecomment-5057506832),
and [epic #50's own 13:04Z
flag](https://github.com/heavy-duty/ceremony/issues/50#issuecomment-5058713181),
which surfaced only because a human happened to look. This file records how
the fleet actually runs; that is why this wiring changed (#50 D16). The spec
for the box-side update:

- **The second query.** Alongside the `state:needs-human` PR poll, `notify.sh`
  polls **open issues and PRs labelled `needs-ruling`** across every repo in
  `~/duty/repos.txt`.
- **One tracked message per item, edited in place** — the same
  one-message-per-item discipline the PR poll already uses, so an aging
  ruling reads as a **live queue**, not a feed. The message is removed when
  the flag comes off. Never one notification per rung: a rung crossing
  changes the text of the existing message and does not page again.
- **The message carries what makes the ruling decidable at a glance:** the
  item, the decision line (the escalation comment's first line), the flag's
  age, and the current rung.
- **Rungs are the message's content, never its trigger.** The four rungs are
  [the ladder's](https://github.com/heavy-duty/ceremony/blob/cb3d482b8be5c6563374a8c52159287fad43644d/LABELS.md#L94-L112)
  — **0–12h**, **at 12h**, **at 24h**, **past 24h** — with the age measured
  from the current episode's `needs-ruling` `labeled` event, the same anchor
  the board-side sweep reads. Division of labor: #73's sweep comments put the
  rungs on the board for the fleet; the notifier puts them in the operator's
  queue. Neither decides.
- **What is worth alerting on:** a `needs-ruling` past its stated `Default:`
  deadline, or standing past 24h, is the fleet-health signal — not the
  flag's existence. An escalation resolved inside its window is working as
  designed and deserves a quiet queue entry, not an alarm.

Nothing box-side ever sets, clears, or decides `needs-ruling` (#50 D9, D15):
the notifier and triage's past-24h wake above *report and pick up* what the
board already shows; the label itself moves only by the doctrine's hands.

`~/duty/repos.txt` and the duty scripts live inside each box and are the
operator's to change; this descriptive edit is the spec for those box-side
updates. The reviewers' request sweep is one such spec made real — deployed
on all four reviewer boxes since 2026-07-23 (the Reviewers wake above). The
notifier's `needs-ruling` queue is still on paper only: `notify.sh`'s one
label filter today is `state:needs-human`.

### Resilience

- **Boot gate:** each tick compares the kernel boot id
  (`/proc/sys/kernel/random/boot_id`) to a stored marker. First tick after any
  reboot runs credential + disk probes; the marker is written only when auth
  actually works, so a box with dead credentials re-checks loudly every tick
  instead of silently skipping duty.
- **Crash-only resume:** there is no session state to restore. The recovery
  path *is* the normal path: the resume wake condition reads the board, posts
  `⟲ resuming from <sha>`, and continues from the worklog. Rebooting a box
  never loses work that was pushed.
- **Checkpoint discipline (builders):** open the PR as draft at the first
  commit with a `## Worklog` checkbox list; check off and push after every
  step. The board and the branch are the only memory.
- **Worktree isolation:** builders build each PR in its own `git worktree`;
  reviewers check out PR heads in throwaway detached worktrees and remove them
  after the verdict. Main clones stay parked on the default branch, always
  clean; stale worktrees are pruned by the boot gate.

### Conventions on the board

- `🔎 reviewing head <sha>` — a reviewer announces work before starting, so
  liveness is visible instead of hoped for.
- `⟲ resuming from <sha>` — a builder announces recovery after interruption.
- Claim ritual: comment on the issue + self-assign + label flip, before any
  branch exists.
- Handoff: the author closes an approved PR's round with a summary comment,
  flips `state:needs-human`, and requests the human — merging is never the
  fleet's job.

## Where this is going

This wiring proved itself on day one (seven merged PRs, unanimous three-model
review convergence on #39, and a full-fleet crash recovery). The plan:

1. Once the ceremony machinery is complete and adopted, each agent will be
   asked to write a **detailed, replicable description of its own setup** —
   cron lines, duty script, prompts, probes — as durable documentation.
2. Those five descriptions get converged into a **solidified fleet-management
   solution** (duty loops as reusable templates, likely living alongside the
   rig templates registry), so standing up this roster on a new repo — or a
   whole new fleet — is a bootstrap, not an archaeology dig.

Until then, this file is the map.
