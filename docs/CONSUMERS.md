# Consumer setup

## Labels automation

The reusable labels workflow owns two independent jobs: additive path-based
`scope:*` labels and reconciliation of PR state, blockers, handoff, and stale
status. The consumer keeps its path mapping in `.github/labeler.yml` and its
review panel plus scope taxonomy in `.github/labels.conf`.

The complete caller is:

```yaml
name: labels
on:
  schedule: [{cron: "*/15 * * * *"}] # advisory; the handoff label is the real wake
  workflow_dispatch:                 # bootstraps missing labels on a fresh repo
  pull_request_target:
    types: [opened, reopened, ready_for_review, converted_to_draft, synchronize, labeled, unlabeled]
permissions:
  contents: read
  issues: write
  pull-requests: write
jobs:
  labels:
    uses: heavy-duty/ceremony/.github/workflows/labels.yml@<pinned-tag>
```

`pull_request_target` is intentional: fork PRs need the base repository's
token to write labels. The reusable workflow executes no PR code. It checks
out only the consumer's base branch and the pinned ceremony implementation.

`.github/labels.conf` has one mandatory panel setting followed by zero or
more scope rows:

```text
panel=claude-bot example-codex-bot example-grok-bot
scope:cli|C5DEF5|The command-line surface
scope:docs|C5DEF5|Documentation
```

The panel is whitespace-separated. Label rows use exactly
`name|color|description`; blank lines are ignored and extra pipes are refused.
Core state, blocker, work-queue, and release labels come from ceremony. Scope
rows remain consumer-owned because paths and surfaces differ by repository.

After adding the caller and configuration, run `workflow_dispatch` once to
bootstrap labels on a fresh repository. Scheduled and PR-triggered runs only
reconcile; they do not repeatedly upsert the taxonomy.
