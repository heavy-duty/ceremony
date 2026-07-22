#!/usr/bin/env bash
# The self-ref pin guard (issue #9; #1 D3). The reusable workflows carry a
# literal `CEREMONY_SELF_REF: "X.Y.Z"` — the ref consumers' runs check this
# repo out at — because a called workflow file arrives without its
# repository, and checkout `ref:`s must be literals. A stale pin must fail
# CI HERE, not a consumer's release. The rules, keyed on this repo's own
# version state (they presume #11's dogfood tree; before it, no VERSION
# exists and the rules cannot bind yet):
#
#   * bare VERSION  → pin == VERSION (the ceremony PR stamps the pin to the
#     version it releases — the third stamp, alongside VERSION and the
#     changelog).
#   * -dev VERSION  → pin == the newest stamped `## X.Y.Z` heading in
#     CHANGELOG.md (the last release — reverse-chronological, so the first
#     bare-X.Y.Z heading from the top; whole-field match, so an rc heading
#     never satisfies it). No stamped heading yet (the pre-first-release
#     tree) → pin == VERSION with -dev stripped.
#
# The self-consumption bypass in release.yml means the pin is never
# load-bearing for this repo's own releases — only for consumers'.
#
# Usage: self-ref-check.sh [tree-dir]   (default: the repo root — the CI
# step; tests point it at fixture trees)
set -euo pipefail

# shellcheck source=lib/version.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../lib/version.sh"

tree="${1:-.}"

fail() {
  printf '%s\n' "$@" >&2
  exit 1
}

# Every workflow carrying the pin must agree — labels.yml carries its own
# copy of the same env (one pin governs machinery and doctrine alike).
shopt -s nullglob
pins=()
carriers=()
for wf in "$tree"/.github/workflows/*.yml; do
  pin="$(awk -F'"' '/^[[:space:]]*CEREMONY_SELF_REF:/ { print $2; exit }' "$wf")"
  [ -n "$pin" ] || continue
  pins+=("$pin")
  carriers+=("$wf")
done

if [ "${#pins[@]}" -eq 0 ]; then
  fail "self-ref-check: no CEREMONY_SELF_REF found under $tree/.github/workflows — the guard has nothing to guard, which is itself a failure (the reusable workflows carry the pin)."
fi

pin="${pins[0]}"
for i in "${!pins[@]}"; do
  if [ "${pins[$i]}" != "$pin" ]; then
    for j in "${!pins[@]}"; do
      echo "  ${carriers[$j]}: ${pins[$j]}" >&2
    done
    fail "self-ref-check: the pins disagree — every workflow must name the same ceremony release."
  fi
done

if [ ! -f "$tree/VERSION" ]; then
  # The pre-dogfood window: #11 adds VERSION and CHANGELOG.md, and this
  # branch dies with it (VERSION, once added, never leaves). Until then the
  # rules have no version state to key on.
  echo "NOTICE: no VERSION file — the pre-dogfood tree (#11 adds it). The pin rules key on the version state and cannot bind yet; pin is '$pin', unchecked."
  exit 0
fi

ver="$(version_read file "$tree")"

if version_is_dev "$ver"; then
  want=""
  if [ -f "$tree/CHANGELOG.md" ]; then
    # mawk-compatible; whole-field match so 0.7.0-rc1 never satisfies the
    # bare shape (#1 constraint 7).
    want="$(awk '$1 == "##" && $2 ~ /^[0-9]+\.[0-9]+\.[0-9]+$/ { print $2; exit }' "$tree/CHANGELOG.md")"
  fi
  if [ -n "$want" ]; then
    reason="the newest stamped CHANGELOG.md heading (the last release)"
  else
    want="${ver%-dev}"
    reason="VERSION with -dev stripped (no release stamped yet)"
  fi
else
  want="$ver"
  reason="VERSION on a bare tree (the ceremony PR stamps the pin to the version it releases)"
fi

if [ "$pin" != "$want" ]; then
  fail "self-ref-check: CEREMONY_SELF_REF is '$pin' but must be '$want' — $reason. A stale pin fails CI here, not a consumer's release."
fi

echo "self-ref-check: pin '$pin' agrees with the tree ($reason)."
