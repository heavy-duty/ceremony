#!/usr/bin/env bash
# Contract tests for actions/drill-recorded (issue #7). Constructed fixture
# trees — a dir with a drills/ directory plus a VERSION file or
# package.json, not git repos — the same discipline as the box suite this
# guard is ported from. set -u, not -e: failing commands are behavior for
# the harness to inspect.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=test/harness.sh
. "$ROOT/test/harness.sh"

SCRIPT="$ROOT/actions/drill-recorded/drill-recorded.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# The guard reads the consumer's tree at its working directory, so every
# case runs from inside a constructed fixture tree.
in_tree() {
  local dir="$1"
  shift
  (cd "$TMP/$dir" && bash "$SCRIPT" "$@")
}

# tree <name> <version> — a fixture tree with a VERSION file and no drills
# dir; cases add records themselves.
tree() {
  mkdir -p "$TMP/$1"
  printf '%s\n' "$2" >"$TMP/$1/VERSION"
}

# pkg_tree <name> <version> — the same, package-json backend.
pkg_tree() {
  mkdir -p "$TMP/$1"
  printf '{ "name": "fixture", "version": "%s" }\n' "$2" >"$TMP/$1/package.json"
}

# record <tree> <version> <body> — write drills/<version>.md in the tree.
record() {
  mkdir -p "$TMP/$1/drills"
  printf '%s\n' "$3" >"$TMP/$1/drills/$2.md"
}

# --- the -dev row: nothing to assert, and the log says why -------------------

tree dev-tree 0.9.1-dev
check "-dev tree with no drills dir at all passes" 0 "nothing to assert" \
  in_tree dev-tree
check "-dev pass names the version it keyed on" 0 "0.9.1-dev" in_tree dev-tree

# --- the bare rows: the record file is the whole gate ------------------------

tree bare-recorded 0.9.0
record bare-recorded 0.9.0 "Ran the drill on real hardware; all green."
check "bare + recorded drill passes" 0 "drills/0.9.0.md" in_tree bare-recorded

tree bare-missing 0.9.0
mkdir -p "$TMP/bare-missing/drills"
check "bare + missing record fails" 1 "drills/0.9.0.md" in_tree bare-missing
check "bare + missing record says the release is unproven" 1 "unproven" \
  in_tree bare-missing

tree bare-no-dir 0.9.0
check "bare + no drills dir at all fails the same way" 1 "drills/0.9.0.md" \
  in_tree bare-no-dir

# The `sed '/./,$!d'` lesson: a record of only whitespace is not a record.
tree bare-blank 0.9.0
mkdir -p "$TMP/bare-blank/drills"
printf ' \t\n\n' >"$TMP/bare-blank/drills/0.9.0.md"
check "bare + whitespace-only record fails" 1 "drills/0.9.0.md" in_tree bare-blank
check "blank-record failure is the same message family" 1 "unproven" \
  in_tree bare-blank

# Prefix confusion is unrepresentable — '0.9.0-rc1.md' is a different path
# than '0.9.0.md' — and this row asserts it STAYS that way.
tree bare-rc-only 0.9.0
record bare-rc-only 0.9.0-rc1 "The candidate's drill."
check "bare 0.9.0: an rc's record never satisfies it" 1 "drills/0.9.0.md" \
  in_tree bare-rc-only

# An rc is a pre-release, not a dev tree (#3's version_is_dev): it ships, so
# it keys bare and wants its own record.
tree rc-recorded 1.0.0-rc1
record rc-recorded 1.0.0-rc1 "Drilled the candidate."
check "rc keys as bare, its own record passes" 0 "drills/1.0.0-rc1.md" \
  in_tree rc-recorded

tree rc-missing 1.0.0-rc1
check "rc keys as bare, no record fails" 1 "drills/1.0.0-rc1.md" \
  in_tree rc-missing

# --- degenerate version sources ----------------------------------------------

mkdir -p "$TMP/no-version"
check "missing version source fails" 1 "cannot read the version" \
  in_tree no-version

mkdir -p "$TMP/empty-version"
printf '\n' >"$TMP/empty-version/VERSION"
check "empty version source fails" 1 "cannot read the version" \
  in_tree empty-version

tree unknown-backend 0.9.0
check "unknown version-source refused" 1 "unknown backend" \
  in_tree unknown-backend drills carrier-pigeon

# --- the package-json backend ------------------------------------------------

pkg_tree pkg-recorded 0.3.0
record pkg-recorded 0.3.0 "Promotion drill ran; notes attached."
check "package-json: bare + recorded passes" 0 "drills/0.3.0.md" \
  in_tree pkg-recorded drills package-json

pkg_tree pkg-missing 0.3.0
check "package-json: bare + missing record fails" 1 "drills/0.3.0.md" \
  in_tree pkg-missing drills package-json

# --- a non-default drills dir ------------------------------------------------

tree alt-dir 0.9.0
mkdir -p "$TMP/alt-dir/evidence"
printf 'Ran it.\n' >"$TMP/alt-dir/evidence/0.9.0.md"
check "a non-default drills-dir is honored" 0 "evidence/0.9.0.md" \
  in_tree alt-dir evidence

# --- the action's wiring: inputs arrive as env vars --------------------------

tree env-tree 0.9.0
mkdir -p "$TMP/env-tree/evidence"
printf 'Ran it.\n' >"$TMP/env-tree/evidence/0.9.0.md"
# A non-default drills dir proves the env var is honored, not the default.
env_tree() {
  (cd "$TMP/env-tree" && DRILLS_DIR=evidence VERSION_SOURCE=file bash "$SCRIPT")
}
check "env vars drive the script the way action.yml does" 0 "evidence/0.9.0.md" \
  env_tree

summary
