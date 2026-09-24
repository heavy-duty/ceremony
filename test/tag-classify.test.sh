#!/usr/bin/env bash
# The tag door has three intentional outcomes (#497): version-shaped tags
# release, declared non-release namespaces no-op, and every other tag reaches
# the existing loud tree-version assertion.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=test/harness.sh
# shellcheck disable=SC1091
. "$ROOT/test/harness.sh"

CLASSIFY="$ROOT/lib/tag-classify.sh"
WORKFLOW="$ROOT/.github/workflows/release.yml"

classify() { # $1 = tag, $2 = namespace
  env TAG="$1" NON_RELEASE_NAMESPACE="$2" bash "$CLASSIFY"
}

assert_step_head() {
  local line
  line="$(grep -nF -- "- name: the tag must name the tree's own version" "$WORKFLOW" | cut -d: -f1)"
  sed -n "$line,$((line + 4))p" "$WORKFLOW"
}

non_release_gate_count() {
  awk '
    BEGIN { quote = sprintf("%c", 39) }
    /^  release-on-tag:$/ { tag = 1 }
    tag && index($0, "if: steps.classify.outputs.classification != " quote "non-release" quote) { count++ }
    END { print count + 0 }
  ' "$WORKFLOW"
}

assertion_gate() {
  assert_step_head | grep -F "if: steps.classify.outputs.classification != 'non-release'"
}

assertion_body() {
  awk '
    /- name: the tag must name the tree.s own version/ { step = 1; next }
    step && /^        run: \|$/ { body = 1; next }
    body && /^          / { print substr($0, 11); next }
    body { exit }
  ' "$WORKFLOW"
}

assertion_failure_is_exact() {
  local body output rc expected
  body="$(assertion_body)"
  output="$(
    cd "$TMP" || exit
    env CEREMONY_DIR="$ROOT" VERSION_SOURCE=file \
      GITHUB_REF_NAME=malformed-tag GITHUB_OUTPUT="$TMP/output" \
      bash -c "$body" 2>&1
  )"
  rc=$?
  expected="$(printf '%s\n' \
    "tag 'malformed-tag' does not match the tree's version '1.2.3' — creating nothing." \
    "A release is a PR, then a tag: the release PR bumps the version and stamps the changelog; the tag goes on its MERGE commit. Delete this tag and re-tag the right commit.")"
  [ "$rc" -eq 1 ] && [ "$output" = "$expected" ]
}

invalid_equal_version_preserves_release_path() {
  local tree body output
  tree="$TMP/invalid-equal-version"
  mkdir -p "$tree"
  printf '1.2.3-dev\n' >"$tree/VERSION"

  [ "$(classify 1.2.3-dev "")" = "classification=invalid" ] || return
  body="$(assertion_body)"
  (
    cd "$tree" || exit
    env CEREMONY_DIR="$ROOT" VERSION_SOURCE=file \
      GITHUB_REF_NAME=1.2.3-dev GITHUB_OUTPUT="$tree/output" \
      bash -c "$body"
  ) || return

  output="$(cat "$tree/output")"
  [ "$output" = "$(printf 'ver=1.2.3-dev\ntag=1.2.3-dev')" ] && [ "$(non_release_gate_count)" = "4" ]
}

# --- release tracks (#618): a literal tag prefix per track --------------------

classify_track() { # $1 = tag, $2 = prefix, $3 = namespace
  env TAG="$1" TAG_PREFIX="$2" NON_RELEASE_NAMESPACE="${3-}" bash "$CLASSIFY"
}

# track_assert <tree> <track> <prefix> <tag> — the real assertion body, run in
# a constructed repository with the track's environment.
track_assert() {
  local body
  body="$(assertion_body)"
  (
    cd "$1" || exit
    env CEREMONY_DIR="$ROOT" VERSION_SOURCE=file TRACK_PATH="$2" TAG_PREFIX="$3" \
      GITHUB_REF_NAME="$4" GITHUB_OUTPUT="$1/output" \
      bash -c "$body"
  )
}

track_assert_publishes() {
  local tree="$TMP/two-tracks"
  rm -f "$tree/output"
  track_assert "$tree" apps/admin admin- admin-2.1.0 || return
  [ "$(cat "$tree/output")" = "$(printf 'ver=2.1.0\ntag=admin-2.1.0')" ]
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
printf '1.2.3\n' >"$TMP/VERSION"

check "a final version remains a release" 0 "classification=release" \
  classify 1.2.3 ""
check "an rc remains a release" 0 "classification=release" \
  classify 1.2.3-rc4 ""
check "a version wins even over an all-matching namespace" 0 "classification=release" \
  classify 1.2.3 '**'

check "a declared drill namespace is a clean no-op" 0 "classification=non-release" \
  classify drill/0.1.2-a877cd9 'drill/**'
check "the no-op log names the namespace" 0 \
  "matched declared non-release namespace 'drill/**'" \
  classify drill/0.1.2-a877cd9 'drill/**'
check "the no-op log names why no release work runs" 0 \
  "skipping release publication and version assertion; creating nothing" \
  classify drill/0.1.2-a877cd9 'drill/**'

check "the same drill tag without a declaration reaches the assertion" 0 \
  "classification=invalid" classify drill/0.1.2-a877cd9 ""
check "a non-matching declaration cannot create a fallthrough no-op" 0 \
  "classification=invalid" classify malformed-tag 'drill/**'
check "a malformed tag with no declaration preserves the assertion path" 0 \
  "classification=invalid" classify malformed-tag ""
check "the invalid-tag failure remains byte-identical" 0 "" \
  assertion_failure_is_exact
check "an invalid-shaped tag equal to the tree version keeps the legacy release path" 0 "" \
  invalid_equal_version_preserves_release_path

mkdir -p "$TMP/two-tracks/apps/admin"
printf '1.6.0\n' >"$TMP/two-tracks/VERSION"
printf '2.1.0\n' >"$TMP/two-tracks/apps/admin/VERSION"

check "a prefixed version is the track's release" 0 "classification=release" \
  classify_track admin-2.1.0 admin-
check "a prefixed rc is the track's release" 0 "classification=release" \
  classify_track admin-2.1.0-rc1 admin-
check "the prefix is literal: a missing dash is not the track's tag" 0 \
  "classification=invalid" classify_track admin2.1.0 admin-
check "the prefix is literal: a 'v' after it is not a version" 0 \
  "classification=invalid" classify_track admin-v2.1.0 admin-
check "a bare version is not a prefixed track's release" 0 \
  "classification=invalid" classify_track 2.1.0 admin-
check "the other track's bare tags no-op when declared" 0 \
  "classification=non-release" classify_track 1.6.0 admin- '[0-9]*'
check "the default track no-ops on a declared prefixed track" 0 \
  "classification=non-release" classify_track admin-2.1.0 "" 'admin-*'
check "the prefix is not a glob: '*' is refused" 1 \
  "must start with a letter" classify_track anything '*'
check "a prefix starting with a digit is refused" 1 \
  "must start with a letter" classify_track 1-2.1.0 1-
check "the assertion reads the track's VERSION and outputs the prefixed tag" 0 "" \
  track_assert_publishes
check "a track tag naming the wrong version refuses, naming the expected tag" 1 \
  "does not match the track's tag 'admin-2.1.0' (version '2.1.0' in 'apps/admin')" \
  track_assert "$TMP/two-tracks" apps/admin admin- admin-2.0.9
check "the default track still reads the root VERSION beside a track" 1 \
  "does not match the tree's version '1.6.0'" \
  track_assert "$TMP/two-tracks" . "" 2.1.0

# The classifier runs before the version assertion; every release-side step
# is then explicitly gated. This makes the no-op perform no version read,
# notes assembly, artifact hook, or publish rather than relying on fallthrough.
check "the tree-version assertion is gated by classification" 0 \
  "if: steps.classify.outputs.classification != 'non-release'" assertion_gate
check "assertion and all publication-side steps skip only a declared non-release tag" 0 "4" \
  non_release_gate_count

summary
