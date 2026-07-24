# Drills

What a drill means in this repo: an **end-to-end rehearsal of both doors of
the release workflow on a disposable repo**. The contract suite proves every
decision offline — facts → decide → notes against fixtures, the merge door's
step sequence replayed in release-exercise.yml — but the doors themselves
only ever run live: gating on a real push event, the tag create, the
publish, the `-dev` re-arm (release.yml's "what is honestly untested"). The
drill is where they run live *before* a version rests on them.

## The rehearsal

1. Create a scratch **private** repo. It is disposable by design — but the
   disposal is split, because the builder cannot perform the delete: at the
   end the builder **archives** it (`PATCH /repos/{owner}/{repo}` with
   `archived: true`, inside the `repo` scope every fleet identity holds),
   and **deleting it is the operator's step** — `delete_repo` is
   deliberately absent from bot tokens, fleet doctrine and not a
   misconfiguration, so no builder that will ever run a drill can do it.
   Do not retry the delete and do not wait on it: both 0.2.0 drills ended
   at that wall independently (#135) — one builder held its release draft
   in `state:building` re-trying a 403 that cannot succeed, the other wrote
   a record asserting a delete that had not happened. **Cleanup gates
   nothing** — not ready-for-review, not the review panel, not the merge.
   The archived leftover is safe to leave: private, no consumers, and
   outside `heavy-duty/ceremony`'s ref namespace — the namespace the
   "never a branch named like the tag" rule below protects.
2. Install the docs/CONSUMERS.md caller stubs, pinned to a fork ref carrying
   the release candidate tree. The candidate's `CEREMONY_SELF_REF` is by
   construction the tag this release has not created yet, so the consumer
   path cannot resolve directly from the candidate. Rewrite that pin to a
   canonical candidate SHA in every carrier on the fork ref, and record the
   fork ref and rewritten pin in the drill record.

   Never create a branch named like the tag on `heavy-duty/ceremony` to
   paper over this deadlock: it would shadow the tag for every consumer
   until someone remembers to delete it. The 0.1.0 drill (#11) is the
   worked example of this standing fork-ref shape.
3. Give it a fixture `VERSION` / `CHANGELOG.md` / `changelog.d/` /
   `drills/` in the armed state (`X.Y.Z-dev`, the fragments directory with
   its `README.md` marker plus at least one fragment for the ceremony to
   consume).
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
record is the evidence; the scratch repo is the evidence's scaffolding. The
record names the scratch repo by full `owner/name` and states its disposal
state **as its author observed it when the record was written** — archived
and pending the operator's delete, or deleted only if the author genuinely
performed the delete. Never a disposal the author did not observe: the
record is the only thing that survives the drill, and 0.2.0's record shipped
its first draft asserting a cleanup that had not happened (#135) — false
evidence in the one file whose job is to be evidence.

`actions/drill-recorded` refuses any bare-version tree whose record is
missing or blank. A waived drill is still a record: the file says WAIVED and
why — a maintainer's call, visible and reviewable in the release PR's diff,
never a silent skip.
