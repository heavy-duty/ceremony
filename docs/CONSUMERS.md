# Consumer setup

## Release workflow

The reusable release workflow implements both doors of the ceremony — the
merge door (merging the `release`-labeled ceremony PR ships it) and the tag
door (a bare `X.Y.Z` tag push as the manual fallback and backfill). The
design essay lives in the workflow's own header comment; the doctrine in
issue #1.

The consumer's **entire** `release.yml`:

```yaml
name: release
# Triggers and permissions MUST live here (a called workflow cannot define them):
on:
  # ONE push key, both filters — YAML maps are last-key-wins; a second sibling
  # `push:` silently replaces the first and kills a door (rig's review catch).
  push:
    tags: ["**"]      # every tag — a wrong tag must FAIL the assert loudly,
                      # never be skipped by a shape filter that didn't match
    branches: [main]
permissions:
  contents: write       # tag ref create + release create + the bump push
  pull-requests: write  # decide's label read; the bump-fallback `gh pr create`
  issues: write         # --label on that fallback PR rides the issues API
jobs:
  release:
    uses: heavy-duty/ceremony/.github/workflows/release.yml@<pinned-tag>
    with:
      version-source: file   # or: package-json
```

`version-source` is the only input: `file` (a `VERSION` file — box, rig,
incubator) or `package-json` (the version field, lockfile kept in sync on
the post-release bump — cast). Everything else a repo might vary is a change
to the ceremony itself, made in this repo, once.

Keep the merge door on `push` to `main` — never `pull_request`: a
`pull_request` run from a public fork gets a read-only `GITHUB_TOKEN` that
`permissions:` cannot raise (box#97), and every ceremony PR in this org is
cross-repo from a bot fork.

Bootstrap the version at `X.Y.Z-dev`, not bare: a first version that never
carried `-dev` hits the decide table's refuse row and has to ship by the
tag door instead (the known first-release edge, cast#111).

### The artifact hook

If the repository contains `.github/actions/release-artifact/action.yml`,
both doors invoke it — after the tag exists, before `gh release create` —
with the release `version` as input and `RELEASE_ASSETS_DIR` exported.
Contract for hook authors:

- Drop finished files into `$RELEASE_ASSETS_DIR`; every file there is
  uploaded as a release asset.
- Exit non-zero to abort the release.
- The hook owns its own toolchain (checkout is done; install node, docker,
  whatever it needs, itself).

A failed hook leaves the tag created but no release published. Recovery is
the tag door's semantics: fix the cause, then delete and re-push the same
tag (the tag door publishes for it), or run `gh release create` by hand from
a fixed tree. The merge door's nothing-exists assert will refuse a re-run of
the completed merge, by design.

No hook → no assets: for a pure-bash tree, GitHub's source tarball for the
tag IS the package.

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

## Doctrine mirror

Machinery is consumed by reference — GitHub fetches the workflows and
actions above from the pin at run time — but documents have no runtime: an
agent reads the working tree it stands in. So the agent-facing doc set
(ceremony's `docs/VENDORED.txt`: AGENTS.md, TRIAGE.md, BUILDER.md,
REVIEWER.md, LABELS.md) is vendored into each consumer at **`.ceremony/`**,
byte-identical to ceremony at the pin, plus a generated `.ceremony/README.md`
marking the directory machine-managed. `actions/docs-sync` owns the copy:
`--fix` writes it (and deletes what the manifest dropped — mirror means
mirror), `--check` re-diffs it in CI on every PR, so a hand edit or a stale
pin goes red instead of quietly governing.

The consumer's ci.yml gains the guard alongside the others:

```yaml
      - uses: actions/checkout@v4
      - uses: heavy-duty/ceremony/actions/docs-sync@<pinned-tag>
```

`mode` defaults to `check`. There is no ref input: the action reads the pin
from the consumer's own `.github/workflows/release.yml` — the same single
`uses: …/release.yml@<ref>` line that pins the machinery, so one pin governs
machinery and doctrine alike, and a second pin cannot fall out of sync.

**Bootstrap on adoption**: add the release and labels callers first (the pin
must exist — the mirror is verified against it), then run `--fix` once from
the repo root and commit `.ceremony/` together with the callers:

```sh
curl -fsSL "https://raw.githubusercontent.com/heavy-duty/ceremony/<pinned-tag>/actions/docs-sync/docs-sync.sh" \
  | bash -s -- --fix
```

If the repo has no root `AGENTS.md`, `--fix` also scaffolds the thin stub
that routes agents to `.ceremony/AGENTS.md` — created once, never
overwritten; it is per-repo content the moment you edit it, so `--check`
asserts only that it exists.

**The pin-bump procedure**: bumping the pin is one PR — the pin line change
plus the re-synced mirror (run `--fix` locally, or let the red `--check` on
the bump PR say what is stale). The guard makes a half-done bump — pin
without mirror, mirror without pin — unmergeable, which is how a process
change rolls out: deliberately, per repo, reviewed.
