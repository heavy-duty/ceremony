#!/usr/bin/env bash
set -euo pipefail

# changelog-monotonic.sh [<base-ref>] [<changelog>] — assert that no SHIPPED
# release heading was DELETED by this branch: the set of '^## X.Y.Z' headings
# on HEAD must be a SUPERSET of the set at the merge base.
#
# Ported from box .github/scripts/changelog-monotonic.sh (the guard's origin:
# box#122, caught in review of box#118), folding in cast's port notes
# (cast#133) — all three repos carried mechanically-identical copies, which
# is issue #1's whole argument for this repo.
#
# The failure it exists to catch leaves no trace either. An author adding an
# entry under '## Unreleased' REPLACES the line below it instead of
# inserting above it:
#
#     -## 0.8.0 — 2026-07-19
#     +## Unreleased
#     +
#     +### Fixed
#     +
#     +- **An entry**
#
# git merges that cleanly — it is a one-line edit inside a file nobody has
# touched concurrently — and the shipped section's whole body is silently
# absorbed into '## Unreleased'. 0.8.0 no longer HAS a section; the heading
# changelog_section (lib/changelog.sh, #4) extracts by is gone, and the next
# release cut from that state republishes 0.8.0's prose as if it were new.
#
# actions/changelog-armed (#5) is green on exactly that tree, correctly: it
# asks only whether the TOP section agrees with the tree's version, and
# deleting '## 0.8.0' leaves '## Unreleased' on top. It is not wrong, it is
# narrow — it guards ONE heading, the one a PR is about to write under. This
# guards the REST of the file, the part no single tree can be asked about at
# all, because "a heading disappeared" is not a property of a tree — it is a
# property of a DIFF.
#
# The rule, and why it needs no tuning: release headings are APPEND-ONLY.
# The ceremony (box#96, #1) adds one and never removes one; nothing else in
# the documented flow touches them. So SUPERSET is exact — it has no
# legitimate violation to carve an exception for. The stamp is covered for
# free: rewriting '## Unreleased' -> '## X.Y.Z — DATE' ADDS X.Y.Z and
# removes no X.Y.Z heading, because 'Unreleased' is not one. '## Unreleased'
# is deliberately NOT in the set this guards — changelog-armed owns that
# heading, keyed on the tree's version, and the ceremony legitimately
# consumes it.
#
# A file of its own, NOT a clause inside changelog-armed.sh, for three
# reasons. Its input is different (a git history, not two files). Its
# degradation is different (no base ref is a SKIP, not a failure). And
# changelog-armed.sh is driven by test/changelog-armed.test.sh against
# constructed two-file trees that are not git repos at all — folding a
# git-dependent assert into it would make every one of those cases either
# skip or lie. Same discipline as lib/changelog.sh: its own file so a test
# can drive it.

base_ref="${1:-${CHANGELOG_MONOTONIC_BASE:-origin/main}}"
changelog="${2:-${CHANGELOG:-CHANGELOG.md}}"

# Fail-closed switch: CI sets it (the action defaults strict to "1"), so a
# SKIP that would be a sensible local degradation becomes a red run there
# instead. A guard that can silently stop guarding is the failure shape this
# whole family of checks exists to refuse, so the skip path is loud and CI
# refuses to take it at all.
strict="${CHANGELOG_MONOTONIC_STRICT:-0}"

skip() {
  if [ "$strict" = "1" ]; then
    echo "changelog-monotonic: $* — and CHANGELOG_MONOTONIC_STRICT=1, so this is a FAILURE, not a skip." >&2
    echo "  CI sets STRICT because a guard that quietly stops guarding is worse than no guard." >&2
    echo "  (Uniqueness on HEAD already passed; it is containment that cannot run.)" >&2
    echo "  Fix the checkout, not this script: the base ref must be fetched (fetch-depth: 0)." >&2
    exit 1
  fi
  echo "changelog-monotonic: containment SKIPPED — $*"
  echo "  (Uniqueness on HEAD already ran and passed — only the deleted-heading"
  echo "   half needs the history. In CI this same condition is a hard failure.)"
  exit 0
}

[ -f "$changelog" ] || { echo "changelog-monotonic: no such file: $changelog" >&2; exit 1; }

# The set of RELEASE headings: '## <token> ...' where <token> looks like a
# version. Field $2, the same split changelog_section (lib/changelog.sh) and
# changelog-armed.sh use, so the three cannot disagree about what a section
# header is. 'Unreleased' fails the shape and is excluded by construction.
# The WHOLE field is the set member, so 0.7.0 and 0.7.0-rc1 are distinct and
# one can never stand in for the other.
headings_raw() {
  awk '
    /^## / && $2 ~ /^[0-9]+\.[0-9]+\.[0-9]+/ { print $2 }
  '
}
headings() { headings_raw | sort -u; }

# --- uniqueness on HEAD (the box#118 class) ----------------------------------
# Containment catches a DELETED heading. It cannot catch a DUPLICATED one: the
# duplicate is head-side SURPLUS, and `comm -23` (base minus head) is blind to
# extras on the head side — with or without `sort -u`, base {0.8.0} minus head
# {0.8.0, 0.8.0} is empty. Multiset comparison does not close it either, for
# the same reason. The assert that does is uniqueness of version headings ON
# HEAD, kept alongside containment rather than replacing it.
#
# This is the shape box#118's bad rebase actually produced: two
# `## 0.8.0 — 2026-07-19` headings with the incoming entry between them. Every
# other guard stayed green — markers absent, the arming rule happy (the top
# section was still right), tests and shellcheck clean — while box's
# extractor, which had no `exit` and re-armed its grab on every matching
# '## ' line, folded post-cut prose into the shipped release body. This
# repo's changelog_section stops at the second heading (`if (found) exit`) —
# same class, milder symptom: the body TRUNCATES at the first copy, and an
# entry stranded between the copies is silently dropped from this release's
# notes and the next's alike (cast#133 documents both extractor shapes).
#
# Nothing legitimate repeats a version heading: the ceremony stamps a NEW
# version, and 'Unreleased' fails the version shape and never reaches here.
dupes="$(headings_raw < "$changelog" | sort | uniq -d)"
if [ -n "$dupes" ]; then
  {
    echo "changelog-monotonic: $changelog has DUPLICATE release heading(s):"
    echo
    printf '%s\n' "$dupes" | sed 's/^/    ## /'
    echo
    cat <<EOF
  Each version heading must appear exactly once. A repeat splits one release
  into two same-named sections, and changelog_section extracts from the FIRST
  match only — so the published body for that version truncates there, and an
  entry stranded between the copies is dropped from the NEXT release's notes
  as well.

  This is the box#118 shape: an entry meant for '## Unreleased' was inserted
  after a shipped heading, and the heading re-added below it. The fix is one
  heading, with the entry above it under '## Unreleased':

      ## Unreleased

      ### Fixed

      - **Your entry**

      ## $(printf '%s\n' "$dupes" | head -1) — DATE     <- exactly once

  Quick check on any changelog-touching rebase:

      diff <(git show origin/main:$changelog | grep '^## ') <(grep '^## ' $changelog)
EOF
  } >&2
  exit 1
fi

# --- everything below needs the HISTORY ------------------------------------
# Uniqueness is settled. What follows is containment, which compares HEAD
# against the merge base and therefore genuinely depends on the base ref, the
# merge base, and the base blob. Each of those can be unavailable for reasons
# that are not the author's fault (a shallow clone, a fork checkout without
# the upstream remote, the commit that first adds the changelog), so each
# degrades rather than failing — which is exactly why the uniqueness half must
# NOT live down here (box#143). It asks nothing of the history, and gating it
# behind these conditions let a duplicate exit 0 on a message about deletion.

git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || skip "not inside a git work tree, so there is no history to compare against"

git rev-parse --verify --quiet "$base_ref^{commit}" >/dev/null \
  || skip "base ref '$base_ref' does not resolve here (a shallow clone, or a fork checkout without the upstream remote)"

merge_base="$(git merge-base "$base_ref" HEAD 2>/dev/null || true)"
[ -n "$merge_base" ] \
  || skip "no merge base between '$base_ref' and HEAD (unrelated histories, or a clone too shallow to reach one)"

# The changelog may not exist at the merge base at all (the commit that adds
# it). Nothing to have deleted, so nothing to assert.
base_file="$(git show "$merge_base:$changelog" 2>/dev/null || true)"
[ -n "$base_file" ] || {
  echo "changelog-monotonic: $changelog does not exist at the merge base ($(git rev-parse --short "$merge_base")) — nothing could have been deleted (uniqueness on HEAD already passed)."
  exit 0
}

base_headings="$(printf '%s\n' "$base_file" | headings)"
head_headings="$(headings < "$changelog")"

# comm -23: lines in the base set that are NOT in the head set — exactly the
# headings this branch removed.
missing="$(comm -23 <(printf '%s\n' "$base_headings") <(printf '%s\n' "$head_headings"))"

if [ -n "$missing" ]; then
  {
    echo "changelog-monotonic: this branch DELETES release heading(s) from $changelog:"
    echo
    printf '%s\n' "$missing" | sed 's/^/    ## /'
    echo
    cat <<EOF
  Present at the merge base ($(git rev-parse --short "$merge_base")), absent on HEAD.

  Release headings are APPEND-ONLY. The ceremony adds one (box#96, #1);
  nothing ever legitimately removes one. So this is not a judgement call — it
  is a defect, and almost always the same one (box#122, caught in review of
  box#118): an entry written under '## Unreleased' REPLACED the heading below
  it instead of being inserted ABOVE it. The shipped section's body is now
  sitting under '## Unreleased', and the version it belonged to has no
  section at all.

  Nothing else will say so. git merges that edit cleanly — no conflict, no
  signal — and changelog-armed stays green, because the TOP section is
  still the right one for this tree's version. The damage surfaces at the
  NEXT release, when changelog_section cannot find the section it extracts
  by heading, or worse, republishes the absorbed prose as if it were new.

  The fix is to put the heading back and INSERT above it, never over it:

      ## Unreleased

      ### Fixed

      - **Your entry**

      ## $(printf '%s\n' "$missing" | head -1) — DATE     <- untouched, still here

  If you are genuinely renaming a released version, that is a rewrite of
  history this guard is meant to stop; say so in the PR and change the guard
  deliberately, in its own commit.
EOF
  } >&2
  exit 1
fi

count="$(printf '%s\n' "$base_headings" | grep -c . || true)"
head_count="$(printf '%s\n' "$head_headings" | grep -c . || true)"

# The success line has two honest forms, because this step runs on two shapes
# of event. On a push to main the merge base IS HEAD: containment compared
# the file against itself and asserted nothing, and deletion is undetectable
# on that event by construction. Reporting "all N still present" there would
# be the same dishonesty the skip messages were fixed for — a log claiming a
# check that did no work. Uniqueness is the half that actually ran, so that
# is the half the line names.
if [ "$merge_base" = "$(git rev-parse HEAD)" ]; then
  echo "changelog-monotonic: containment vacuous (the merge base IS HEAD, so nothing could have been deleted between them) — uniqueness on HEAD checked $head_count release heading(s)."
else
  echo "changelog-monotonic: all $count release heading(s) at the merge base ($(git rev-parse --short "$merge_base")) are still present in $changelog"
fi
