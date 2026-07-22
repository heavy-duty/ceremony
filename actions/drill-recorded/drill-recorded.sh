#!/usr/bin/env bash
set -euo pipefail

# drill-recorded.sh [<drills-dir>] [<version-source>] — assert that a
# RELEASE tree carries a drill record: that the ritual this repo says a
# release rests on was actually run for this version, and written down as
# <drills-dir>/<version>.md.
#
# Ported from box .github/scripts/drill-recorded.sh (the origin); rig and
# cast carry their own rephrasings of the same rule, and this action is the
# one copy they all converge on (#13–#16).
#
# Why it exists: box's CONTRIBUTING said since box#96 that "this PR is where
# the release ritual hangs: the full drill on real hardware, recorded". No
# release ever did it. box#95, box#114 and box#148 all shipped as a VERSION
# bump plus a CHANGELOG.md stamp and nothing else. That is three releases
# through the same gap, because the gate was a sentence in a document and
# the only thing standing on it was a reviewer remembering to ask. A
# reviewer finally did — which is the point: the ONE time it was caught is
# the time somebody happened to look, and that is not a gate, it is luck
# with good manners. So the rule moves into CI, where it fires on every
# release PR whether or not anyone is paying attention.
#
# It is keyed on the tree's version for the same reason changelog-armed is —
# the two states are genuinely different:
#
#   version ends in -dev  ->  PASS. A development tree ships nothing, so
#                             there is nothing for it to have proven. Almost
#                             every PR in a consumer repo is this case, and
#                             a guard that nagged all of them would be
#                             turned off.
#   version is bare       ->  the ceremony tree, the one about to ship.
#                             <drills-dir>/<version>.md MUST exist and carry
#                             at least one non-whitespace character.
#
# ONE FILE PER VERSION, and that is the whole design. Records used to be
# sections sharing one file, and every hard edge the old guard had existed
# only because of that sharing: em-dash field matching, an optional
# ' — DATE' tail, whole-version comparison so '0.9.0-rc1' could not satisfy
# '0.9.0', avoiding '\x' escapes because CI runs mawk not gawk, and a
# non-blank body rule to tell an empty section from a filled one. Two
# separate defects were found in review because of that complexity — a
# `sed '/./,$!d'` whitespace bypass, and heading-grammar drift from the
# sibling repos. Splitting the file makes almost all of it UNREPRESENTABLE:
# '0.9.0.md' and '0.9.0-rc1.md' are simply different files, so whole-version
# matching is free rather than a trap, and there is no grammar left to
# drift.
#
# The directory is plain 'drills', NOT '.drills'. A dot-directory is
# invisible to a glob without dotglob, which is exactly what caused box#116
# and box#118; evidence a sweep cannot see is evidence that goes missing
# quietly.
#
# What this guard asserts is a RECORD, deliberately — not a passing drill.
# CI cannot run a consumer's drill: box's wants real hardware, a real Incus,
# and the better part of an hour. What CI can do is refuse to let a release
# claim a ritual it left no evidence of. That also leaves the maintainer
# waiver intact and honest: a release that must ship without a full drill
# records WHY in its own file, which is a deliberate, reviewable commit in
# the diff — rather than the silent skip that let box#95, box#114 and
# box#148 all ship unproven.
#
# What a drill MEANS is the consumer's business (box: the isolation
# contract; rig: convergence; cast: promotion; each names it in its own
# drills/README.md). This guard only ever reads the record file in the tree
# it runs in.
#
# A file of its own (not inlined in action.yml) so
# test/drill-recorded.test.sh can drive it against constructed trees for
# both states — the same discipline as the libs it sources.

drills="${1:-${DRILLS_DIR:-drills}}"
version_source="${2:-${VERSION_SOURCE:-file}}"

# The shared libs travel with this action: a consumer's
# `uses: heavy-duty/ceremony/actions/drill-recorded@<tag>` downloads this
# whole repository at that ref, so ../../lib is always present and always at
# the same ref — no checkout step, no version skew possible.
here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/version.sh
. "$here/../../lib/version.sh"

# A missing or empty version source is an ERROR, never a silent pass. A
# guard that cannot read the version cannot know whether this tree is its
# business, and "could not tell" must not resolve to "allowed". version_read
# refuses loudly on its own; the wrapper line names the guard so a workflow
# log shows which check refused.
ver="$(version_read "$version_source")" || {
  echo "drill-recorded: cannot read the version (version-source: $version_source)" >&2
  exit 1
}

# version_is_dev is the single definition of the -dev special case (#3): an
# rc is a pre-release, not a dev tree — it ships, so it needs its own record
# ('2.0.0-rc1.md'), which one-file-per-version makes just another path.
if version_is_dev "$ver"; then
  # Nothing to assert, and saying so is the point: the operator reading a
  # green log should be able to tell "the guard passed" from "the guard
  # decided this tree was not its business".
  echo "drill-recorded: version '$ver' is a development tree — nothing to assert; only ceremony trees ship"
  exit 0
fi

record="$drills/$ver.md"

# The one rule that survives the rewrite, and it survives because it was
# never really about heading parsing: a file of only spaces, tabs and
# newlines is NOT a record. The first cut of box's guard extracted with
# `sed '/./,$!d'`, where `.` matches a space — so a record whose body was
# one tab satisfied a guard that promised "at least one non-blank line". An
# evidence-free release for the price of an invisible character, on the one
# check whose entire job is to demand evidence. Existence alone is a weaker
# claim than `touch` can defeat, so existence alone is not the test.
if [ ! -f "$record" ] || ! grep -q '[^[:space:]]' "$record"; then
  cat >&2 <<EOF
drill-recorded: the version is '$ver' — a release — and there is no drill
  record for it. The file this looks for is:

    $record

  ...with something written in it. Either the file is absent entirely, or it
  is present and blank; both mean the same thing, which is that this release
  is asserting a ritual it has left no evidence of — this release is
  unproven.

  The unblock is to RUN THE DRILL and record it at that path — what it
  measured, what it found, what it cost. See $drills/README.md for what a
  drill means in this repo and what a record should contain. CI cannot run
  the drill for you; it can only refuse a release that never ran one.

  If this release must ship without a full drill, that is a maintainer's
  call to make and it is still recorded: create the same file and say
  plainly that the drill was WAIVED and why. The guard requires a record,
  not a passing result — a failed drill honestly written down satisfies it
  too — so a skip is a visible, reviewable file in the diff rather than the
  silent gap that let box#95, box#114 and box#148 all ship unproven.
EOF
  exit 1
fi

echo "drill-recorded: version '$ver' has a drill record at $record"
