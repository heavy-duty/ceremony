# Drills

What a drill means in this repo: an **end-to-end rehearsal of both doors of
the release workflow on a disposable repo**. The contract suite proves every
decision offline — facts → decide → notes against fixtures, the merge door's
step sequence replayed in release-exercise.yml — but the doors themselves
only ever run live: gating on a real push event, the tag create, the
publish, the `-dev` re-arm (release.yml's "what is honestly untested"). The
drill is where they run live *before* a version rests on them.

## The rehearsal

1. Create a scratch **private** repo. It is disposable by design — it gets
   deleted at the end.
2. Install the docs/CONSUMERS.md caller stubs, pinned to the release
   candidate ref. A branch ref works: refs are static identifiers — the
   family's own drill doctrine.

   **Except for the first release** (learned drilling 0.1.0, #11): the
   stubs' consumer path fetches ceremony at `CEREMONY_SELF_REF` — the very
   ref the first drill exists to rehearse creating — so the pure pinned
   path cannot run before some `X.Y.Z` ref exists, and a branch named like
   the tag must NOT be created on the canonical repo to paper over it (it
   would shadow the tag for every consumer until someone remembers to
   delete it). The first drill instead pins the callers to a fork ref
   carrying the candidate tree with `CEREMONY_SELF_REF` rewritten to the
   candidate SHA in every pin carrier, and records that one-line deviation
   in its record. From the second release on, this paragraph is moot.
3. Give it a fixture `VERSION` / `CHANGELOG.md` / `drills/` in the armed
   state (`X.Y.Z-dev`, `## Unreleased` on top).
4. Exercise both doors, one probe at a time:

   1. a merge-door ceremony publishes exactly one release and re-arms main
      to `-dev`;
   2. a mislabeled ordinary PR is a green NOTICE no-op;
   3. a bare-version PR without the `release` label refuses;
   4. a re-run of the completed ceremony refuses;
   5. a tag-door release from a manual tag;
   6. a mismatched tag refuses.

   Every refusal must refuse **creating nothing** — a probe that leaves a
   tag or a release behind on a refusal path is a failed probe.

## The record

One file per version, `drills/X.Y.Z.md` — the shape the siblings use: what
was run, where, the result of each probe, failures written down plainly. The
record is the evidence; the scratch repo is the evidence's scaffolding and
is deleted afterwards.

`actions/drill-recorded` refuses any bare-version tree whose record is
missing or blank. A waived drill is still a record: the file says WAIVED and
why — a maintainer's call, visible and reviewable in the release PR's diff,
never a silent skip.
