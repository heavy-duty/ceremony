#!/usr/bin/env bash
# lib/decide.sh — the merge door's decision, pure and exhaustively tested
# (issue #8; design lineage: box#96 / rig#47 / cast#111).
#
# The merge-door job runs on EVERY push to main, and the `release` label
# carries TWO legitimate meanings (per each repo's LABELS.md: "release flow
# and version/packaging work"): the ceremony PR that ships a version, and
# ordinary work ON the release machinery — the PR that adds the ceremony to
# a repo included. The version transition tells them apart. Every ambiguous
# middle state is a half-ceremony and must die loudly, creating nothing;
# every legitimate non-ceremony state must be a green NOTICE no-op, not a
# red run on main per infra PR.
#
# Pure: no git, no gh, no network. The caller (the release workflow, #9)
# establishes four facts and passes them as environment variables:
#
#   VER       the version at the pushed head
#   BASE_VER  the version at the base (the head's first parent /
#             event.before — the caller's job, including the
#             all-zeros-event.before fallback)
#   RELEASED  "yes"|"no" — does a release for VER already exist?
#   LABELED   "yes"|"no" — is a merged, release-labeled PR behind this
#             commit?
#
# Output: `ceremony=yes` or `ceremony=no` on stdout (the workflow appends
# it to $GITHUB_OUTPUT), notices to stdout, refusals to stderr, exit 1 on
# refusal.
#
# The decision table (this IS the spec — issue #8):
#
# | # | VER    | vs BASE_VER | RELEASED | LABELED | result                    |
# |---|--------|-------------|----------|---------|---------------------------|
# | 1 | `-dev` | unchanged   | —        | —       | `ceremony=no`, NOTICE:    |
# |   |        |             |          |         | work under the label /    |
# |   |        |             |          |         | ordinary merge — nothing  |
# |   |        |             |          |         | to publish                |
# | 2 | `-dev` | changed     | —        | —       | `ceremony=no`, NOTICE:    |
# |   |        |             |          |         | still a dev tree — the    |
# |   |        |             |          |         | post-release bump or a    |
# |   |        |             |          |         | renumber; "a dev tree is  |
# |   |        |             |          |         | by definition not a       |
# |   |        |             |          |         | release"                  |
# | 3 | bare   | unchanged   | yes      | —       | `ceremony=no`, NOTICE:    |
# |   |        |             |          |         | post-release window       |
# |   |        |             |          |         | (ceremony landed, `-dev`  |
# |   |        |             |          |         | bump hasn't) — nothing to |
# |   |        |             |          |         | publish                   |
# | 4 | bare   | unchanged   | no       | —       | REFUSE (exit 1): "the     |
# |   |        |             |          |         | label says ship but this  |
# |   |        |             |          |         | PR did not mint the       |
# |   |        |             |          |         | version. Refusing to      |
# |   |        |             |          |         | guess — creating          |
# |   |        |             |          |         | nothing."                 |
# | 5 | bare   | changed     | —        | no      | REFUSE (exit 1): "version |
# |   |        |             |          |         | transitioned but no       |
# |   |        |             |          |         | merged, release-labeled   |
# |   |        |             |          |         | PR is behind this commit  |
# |   |        |             |          |         | — a release is a labeled  |
# |   |        |             |          |         | ceremony PR, not a bare   |
# |   |        |             |          |         | push — creating nothing." |
# | 6 | bare   | changed     | —        | yes     | `ceremony=yes`            |
#
# Ordering matters and matches the sources: the -dev cases never consult
# RELEASED or LABELED; the bare-unchanged cases never consult LABELED;
# LABELED is only read after a bare transition is established. RELEASED and
# LABELED may be empty in the states that don't use them — the workflow is
# free to skip API calls it doesn't need — but a state that DOES need one
# refuses when it is empty: a fact-gathering bug upstream must never fall
# through to "no".
#
# State 4 doubles as the known first-release edge (cast#111): a repo whose
# first version never carried -dev ships its first release by the tag door.
# Consumers that bootstrap at X.Y.Z-dev (the docs/CONSUMERS.md guide says
# to) never hit it.
set -euo pipefail

# shellcheck source=lib/version.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/version.sh"

refuse() {
  printf '%s\n' "$@" >&2
  exit 1
}

notice() {
  printf 'NOTICE: %s\n' "$1"
}

# Before the table: a missing fact is a fact-gathering bug upstream and must
# not fall through to "no"; a malformed fact is the same bug wearing a
# different hat.
if [ -z "${VER:-}" ]; then
  refuse "VER is empty — the caller failed to establish the version at the pushed head. Refusing to decide — creating nothing."
fi
if [ -z "${BASE_VER:-}" ]; then
  refuse "BASE_VER is empty — the caller failed to establish the version at the base. Refusing to decide — creating nothing."
fi
case "${RELEASED:-}" in
  yes | no | '') ;;
  *) refuse "RELEASED='${RELEASED}' — expected yes, no, or empty. Refusing to decide — creating nothing." ;;
esac
case "${LABELED:-}" in
  yes | no | '') ;;
  *) refuse "LABELED='${LABELED}' — expected yes, no, or empty. Refusing to decide — creating nothing." ;;
esac

# Rows 1–2: a -dev tree decides on VER and BASE_VER alone. Only -dev is
# special-cased (version_is_dev): an rc is a pre-release, and an rc
# transition with a label is a shippable ceremony.
if version_is_dev "$VER"; then
  if [ "$BASE_VER" = "$VER" ]; then
    notice "the version '$VER' is -dev and unchanged by this PR — release-flow work under the release label, not a ceremony. Nothing to publish."
  else
    notice "the version changed ('$BASE_VER' -> '$VER') and still ends -dev — a dev tree is by definition not a release. This is work (the post-release bump, a renumber); nothing to publish."
  fi
  echo "ceremony=no"
  exit 0
fi

# Rows 3–4: bare and unchanged — RELEASED tells the post-release window
# apart from a label with no minted version. LABELED is not consulted.
if [ "$BASE_VER" = "$VER" ]; then
  case "${RELEASED:-}" in
    yes)
      notice "the version '$VER' is already released and unchanged by this PR — release-flow work merged in the post-release window (before the -dev bump). Nothing to publish."
      echo "ceremony=no"
      exit 0
      ;;
    no)
      refuse \
        "the version '$VER' is bare, unchanged by this PR, and never released — the label says ship but this PR did not mint the version. Refusing to guess — creating nothing." \
        "(If this PR was mislabeled, drop the label; if it was meant to release, it forgot the bump. A first release whose version never carried -dev ships by the tag door — the known first-release edge.)"
      ;;
    *)
      refuse "the version '$VER' is bare and unchanged, but RELEASED is empty — this state is decided by whether '$VER' is already released, and the caller did not establish that fact. Refusing to guess — creating nothing."
      ;;
  esac
fi

# Rows 5–6: a bare transition — now the LABEL, the operator's declared
# intent. No merged, release-labeled PR behind this commit = a transition
# nobody declared: refuse.
case "${LABELED:-}" in
  yes)
    echo "ceremony=yes"
    ;;
  no)
    refuse "the version transitioned ('$BASE_VER' -> '$VER') but no merged, release-labeled PR is behind this commit — a release is a labeled ceremony PR, not a bare push — creating nothing."
    ;;
  *)
    refuse "the version transitioned ('$BASE_VER' -> '$VER') but LABELED is empty — a transition ships only behind a merged, release-labeled PR, and the caller did not establish that fact. Refusing to guess — creating nothing."
    ;;
esac
