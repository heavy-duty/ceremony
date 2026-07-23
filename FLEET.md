# FLEET.md — the roster, and how it actually runs

> **Status:** descriptive snapshot, not doctrine. This file records how the
> agent fleet that builds this repo is wired *today*, so the setup can later be
> solidified into a replicable fleet-management solution. It is **not** part of
> the vendored doctrine set (`.ceremony/`) and is never mirrored to consumer
> repos. The doctrine files (AGENTS.md, TRIAGE.md, BUILDER.md, REVIEWER.md,
> LABELS.md, CONTRIBUTING.md) say what roles *must* do; this file says how the
> current bench *physically* does it.

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
- **Poll:** the script reads `~/duty/repos.txt` (the repo registry — adding a
  repo is adding a line) and queries GitHub with `gh` for work matching the
  box's role.
- **Act:** when there is work, the script launches the box's CLI as a one-shot
  session with a role prompt; the session does the work via `gh` as the box's
  own identity, then exits. Sessions are stateless and disposable — all state
  lives on the board (issues, PRs, labels) and in git branches.

### Wake conditions

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
- **Reviewers**, in priority order: first, a review requested on me in any
  repo (`gh search prs --review-requested=@me --state=open`); second, the
  repo-list poll for an open PR by someone else whose head I have not yet
  reviewed. Both triggers keep the existing one-verdict-per-head rule,
  deduplicated against my own latest review's SHA rather than the search index
  (it lags). The request trigger runs first because it reaches repos the list
  does not name.

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
operator's to change. This descriptive edit is the spec for those box-side
updates; until an operator makes them, the request trigger and the notifier's
`needs-ruling` queue exist on paper only.

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
