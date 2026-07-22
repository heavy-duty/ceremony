#!/usr/bin/env bash
# lib/facts.sh — the merge door's fact gathering (issue #9).
#
# lib/decide.sh (issue #8) is pure: it consumes four facts and renders the
# 5-state verdict. This script is the impure half that establishes those
# facts. It runs inside the consumer's checkout (the working directory),
# talks to git and gh, and prints the facts in $GITHUB_OUTPUT form:
#
#   ver=…  base_ver=…  released=(yes|no|empty)  labeled=(yes|no|empty)
#
# stdout carries exclusively those lines — the release workflow appends the
# whole stream to $GITHUB_OUTPUT — so every diagnostic goes to stderr.
#
# Env in:
#   VERSION_SOURCE      file | package-json (the workflow's one input)
#   MERGE_SHA           the pushed head (github.sha)
#   EVENT_BEFORE        github.event.before — may be empty or all-zeros
#   GITHUB_REPOSITORY   for the two API facts
#   GH_TOKEN            for gh (unused when no API state is consulted)
#
# The API calls run only in the states that consult them (decide tolerates
# empty facts — issue #8): RELEASED only for a bare unchanged version,
# LABELED only for a bare transition. A -dev tree — every ordinary merge —
# decides on the two versions alone and never touches the API.
set -euo pipefail

# shellcheck source=lib/version.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/version.sh"

: "${VERSION_SOURCE:?facts: VERSION_SOURCE is required}"
: "${MERGE_SHA:?facts: MERGE_SHA is required}"

case "$VERSION_SOURCE" in
  file) src=VERSION ;;
  package-json) src=package.json ;;
  *)
    echo "facts: unknown VERSION_SOURCE '$VERSION_SOURCE' — expected file or package-json" >&2
    exit 1
    ;;
esac

ver="$(version_read "$VERSION_SOURCE")"

# event.before is all-zeros on a branch-create push, and absent outside push
# events; the pushed head's first parent is main the instant before, either
# way (#1 constraint 10; cast's `*[!0]*` test — "contains a non-zero char").
base_sha="${EVENT_BEFORE:-}"
case "$base_sha" in
  *[!0]*) ;;
  *) base_sha="$(git rev-parse "$MERGE_SHA^1")" ;;
esac

# Belt-and-braces (cast's precedent): the workflow's fetch-depth: 2 resolves
# the first parent, but event.before can predate it when pushes raced. If
# the fetch still cannot produce it, the git show below is the loud failure.
git cat-file -e "$base_sha" 2>/dev/null \
  || git fetch --depth=1 origin "$base_sha" >&2 \
  || true

base_dir="$(mktemp -d)"
trap 'rm -rf "$base_dir"' EXIT

if git show "$base_sha:$src" >"$base_dir/$src" 2>/dev/null; then
  base_ver="$(version_read "$VERSION_SOURCE" "$base_dir")"
else
  # The base tree has no version source at all: the merge that ADDS the
  # version machinery (a consumer's adoption PR, a greenfield repo's first
  # caller). "(none)" is not a version, so decide sees a changed version
  # and the table still governs: a -dev head is work (row 2, the guided
  # bootstrap path), a bare head still demands the merged release label
  # (rows 5–6). Nothing releases silently either way.
  base_ver="(none)"
fi

released=""
labeled=""
if ! version_is_dev "$ver"; then
  if [ "$base_ver" = "$ver" ]; then
    # Any gh failure reads as "not released" — the sources' semantics; the
    # verdict this feeds (row 4) is a refusal, and the ceremony path
    # re-checks existence in the nothing-exists assert before creating
    # anything.
    if gh release view "$ver" -R "$GITHUB_REPOSITORY" --json name >/dev/null 2>&1; then
      released=yes
    else
      released=no
    fi
  else
    # The sources' exact jq: merged PRs only, `release` among the label
    # names. Read via the API because a push event carries no PR payload —
    # and the PR itself lives on a fork (the trigger comment in the
    # workflow). A failed API call reads as "no label", which row 5
    # refuses: fail-closed.
    if gh api "repos/$GITHUB_REPOSITORY/commits/$MERGE_SHA/pulls" \
        -q '[.[] | select(.merged_at != null) | .labels[].name] | index("release") != null' \
        | grep -qx true; then
      labeled=yes
    else
      labeled=no
    fi
  fi
fi

echo "facts: ver='$ver' base_ver='$base_ver' released='$released' labeled='$labeled'" >&2
printf 'ver=%s\n' "$ver"
printf 'base_ver=%s\n' "$base_ver"
printf 'released=%s\n' "$released"
printf 'labeled=%s\n' "$labeled"
