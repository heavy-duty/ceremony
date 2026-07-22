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
  invariants).
- **Builders**, in priority order: **resume** (an open draft PR of mine, or a
  claimed issue with my `build/*` branch but no PR — possible only if a
  previous session died mid-work), a `ready` issue to claim, a completed
  review round on my PR (act on whole rounds, never single verdicts), my PR
  fully approved (write the closing summary, flip to `state:needs-human`,
  request the human), my PR `CONFLICTING` (rebase; never act on `UNKNOWN` —
  post-merge flap).
- **Reviewers:** an open PR by someone else whose head I have not yet
  reviewed — one verdict per head, deduplicated against my own latest review's
  SHA, not against the search index (it lags).

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
