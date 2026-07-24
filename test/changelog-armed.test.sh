#!/usr/bin/env bash
# Contract tests for actions/changelog-armed (issue #5). Constructed fixture
# trees — a dir with a changelog plus a VERSION file or package.json, not
# git repos — the same discipline as the box suite this guard is ported
# from. set -u, not -e: failing commands are behavior for the harness to
# inspect.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=test/harness.sh
. "$ROOT/test/harness.sh"

SCRIPT="$ROOT/actions/changelog-armed/changelog-armed.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# The guard reads the consumer's tree at its working directory, so every
# case runs from inside a constructed fixture tree.
in_tree() {
  local dir="$1"
  shift
  (cd "$TMP/$dir" && bash "$SCRIPT" "$@")
}

# tree <name> <version> — a fixture tree with a VERSION file; the changelog
# body arrives on stdin.
tree() {
  mkdir -p "$TMP/$1"
  printf '%s\n' "$2" >"$TMP/$1/VERSION"
  cat >"$TMP/$1/CHANGELOG.md"
}

# pkg_tree <name> <version> — the same, package-json backend.
pkg_tree() {
  mkdir -p "$TMP/$1"
  printf '{ "name": "fixture", "version": "%s" }\n' "$2" >"$TMP/$1/package.json"
  cat >"$TMP/$1/CHANGELOG.md"
}

# --- the -dev rows: top section MUST be '## Unreleased' ----------------------

tree dev-armed 1.2.4-dev <<'EOF'
# Changelog

## Unreleased

- Pending entry.

## 1.2.3 — 2026-07-20

- The shipped entry.
EOF
check "-dev + Unreleased on top passes" 0 "agrees" in_tree dev-armed

tree dev-seeded 1.2.4-dev <<'EOF'
# Changelog

## Unreleased

### Added

### Changed

### Fixed

## 1.2.3 — 2026-07-20

### Fixed

- The shipped entry.
EOF
check "-dev + seeded empty Unreleased headings passes" 0 "agrees" in_tree dev-seeded

tree dev-stamped 1.2.4-dev <<'EOF'
# Changelog

## 1.2.3 — 2026-07-20

- The shipped entry.
EOF
check "-dev + stamped top fails" 1 "development tree" in_tree dev-stamped
check "-dev failure names the file" 1 "CHANGELOG.md" in_tree dev-stamped
check "-dev failure teaches the re-arm fix" 1 "re-arm" in_tree dev-stamped

# --- the bare rows: both ceremony shapes legal, half-ceremonies refused -----

tree bare-armed 1.2.3 <<'EOF'
# Changelog

## Unreleased

## 1.2.3 — 2026-07-20

- The shipped entry.
EOF
check "bare + re-armed tree passes" 0 "agrees" in_tree bare-armed

tree bare-stamped 1.2.3 <<'EOF'
# Changelog

## 1.2.3 — 2026-07-20

- The shipped entry.

## 1.2.2 — 2026-07-01

- Older entry.
EOF
check "bare + own stamped section on top passes" 0 "agrees" in_tree bare-stamped

tree bare-dangling-heading 1.2.3 <<'EOF'
# Changelog

## 1.2.3 — 2026-07-20

### Added
EOF
check "bare + dangling heading fails with the heading diagnosis" 1 \
  "section '1.2.3' has no entries — a heading is not an entry" \
  in_tree bare-dangling-heading
check "bare + dangling heading keeps the half-ceremony remedy" 1 \
  "HALF-DONE ceremony" in_tree bare-dangling-heading

tree bare-partly-dangling 1.2.3 <<'EOF'
# Changelog

## 1.2.3 — 2026-07-20

### Added

### Fixed

- Fixed entry.
EOF
check "bare + one empty grouped heading names the first empty heading" 1 \
  "section '1.2.3' has an empty heading: '### Added'" \
  in_tree bare-partly-dangling

tree bare-empty-stamp 1.2.3 <<'EOF'
# Changelog

## 1.2.3 — 2026-07-20

## 1.2.2 — 2026-07-01

- Older entry.
EOF
check "bare + own stamped section but EMPTY fails" 1 "no non-empty" \
  in_tree bare-empty-stamp

tree bare-wrong-stamp 1.2.3 <<'EOF'
# Changelog

## 9.9.9 — 2026-07-20

- An entry under the wrong number.
EOF
check "bare + top section naming another version fails" 1 "stamped the wrong number" \
  in_tree bare-wrong-stamp

tree bare-half-ceremony 1.2.3 <<'EOF'
# Changelog

## Unreleased

- Pending entry that was never stamped.

## 1.2.2 — 2026-07-01

- Older entry.
EOF
check "bare + no section for the version anywhere fails" 1 "HALF-DONE ceremony" \
  in_tree bare-half-ceremony

# Whole-version matching: 1.2.3 must not be satisfied by a 1.2.3-rc1 section.
tree bare-rc-only 1.2.3 <<'EOF'
# Changelog

## Unreleased

## 1.2.3-rc1 — 2026-07-15

- The candidate's entry.
EOF
check "bare: an rc section never satisfies the bare version" 1 "HALF-DONE ceremony" \
  in_tree bare-rc-only

# An rc is a pre-release, not a dev tree (#3's version_is_dev): it keys on
# the bare rules, so a stamped rc section of its own is shippable.
tree rc-stamped 2.0.0-rc1 <<'EOF'
# Changelog

## Unreleased

## 2.0.0-rc1 — 2026-07-20

- The candidate's entry.
EOF
check "rc keys as bare, own stamped section passes" 0 "agrees" in_tree rc-stamped

# --- degenerate trees --------------------------------------------------------

tree no-sections 1.2.3-dev <<'EOF'
# Changelog

Only preamble prose, no sections.
EOF
check "changelog with no '## ' at all fails" 1 "nothing for a PR entry to land under" \
  in_tree no-sections

mkdir -p "$TMP/no-changelog"
printf '1.2.3\n' >"$TMP/no-changelog/VERSION"
check "missing changelog fails" 1 "no such file" in_tree no-changelog

mkdir -p "$TMP/no-version"
printf '# Changelog\n\n## Unreleased\n' >"$TMP/no-version/CHANGELOG.md"
check "missing version source fails" 1 "cannot read the version" in_tree no-version

check "unknown version-source refused" 1 "unknown backend" \
  in_tree dev-armed CHANGELOG.md carrier-pigeon

# --- the package-json backend ------------------------------------------------

pkg_tree pkg-dev-armed 0.2.0-dev <<'EOF'
# Changelog

## Unreleased

- Pending entry.

## 0.1.0 — 2026-07-20

- The shipped entry.
EOF
check "package-json: -dev + armed passes" 0 "agrees" \
  in_tree pkg-dev-armed CHANGELOG.md package-json

pkg_tree pkg-bare-armed 0.1.0 <<'EOF'
# Changelog

## Unreleased

## 0.1.0 — 2026-07-20

- The shipped entry.
EOF
check "package-json: bare + armed passes" 0 "agrees" \
  in_tree pkg-bare-armed CHANGELOG.md package-json

# --- fragment mode: changelog.d/ is the arming -------------------------------

fragment_tree() {
  local name="$1" version="$2"
  shift 2
  tree "$name" "$version"
  mkdir -p "$TMP/$name/changelog.d"
  printf '%s\n' "# Changelog fragments" >"$TMP/$name/changelog.d/README.md"
}

fragment_tree fragments-dev-empty 1.2.4-dev <<'EOF'
# Changelog

## 1.2.3 — 2026-07-20

- The shipped entry.
EOF
check "fragment -dev + marker + no fragments passes" 0 "fragment mode" \
  in_tree fragments-dev-empty

fragment_tree fragments-dev-flat 1.2.4-dev <<'EOF'
# Changelog

## 1.2.3 — 2026-07-20

- The shipped entry.
EOF
printf '%s\n' "- Added fragment mode." >"$TMP/fragments-dev-flat/changelog.d/115.md"
check "fragment -dev + well-formed flat fragment passes" 0 "fragment mode" \
  in_tree fragments-dev-flat

fragment_tree fragments-dev-grouped 1.2.4-dev <<'EOF'
# Changelog

## 1.2.3 — 2026-07-20

### Fixed

- The shipped entry.
EOF
cat >"$TMP/fragments-dev-grouped/changelog.d/115.md" <<'EOF'
### Changed

- Added fragment mode.
EOF
check "fragment -dev + well-formed grouped fragment passes" 0 "fragment mode" \
  in_tree fragments-dev-grouped

fragment_tree fragments-unreleased 1.2.4-dev <<'EOF'
# Changelog

## Unreleased

## 1.2.3 — 2026-07-20

- The shipped entry.
EOF
check "fragment mode refuses even an empty Unreleased section" 1 \
  "Unreleased' section survived the adoption" in_tree fragments-unreleased

fragment_tree fragments-no-marker 1.2.4-dev <<'EOF'
# Changelog

## 1.2.3 — 2026-07-20

- The shipped entry.
EOF
rm "$TMP/fragments-no-marker/changelog.d/README.md"
check "fragment mode requires the generated marker" 1 "README.md" \
  in_tree fragments-no-marker

fragment_tree fragments-bad-name 1.2.4-dev <<'EOF'
# Changelog

## 1.2.3 — 2026-07-20

- The shipped entry.
EOF
printf '%s\n' "- An entry." >"$TMP/fragments-bad-name/changelog.d/notes.md"
check "fragment mode quotes malformed-fragment diagnosis and file" 1 \
  "fragment 'changelog.d/notes.md' is not named for its issue" \
  in_tree fragments-bad-name

fragment_tree fragments-dangling-group 1.2.4-dev <<'EOF'
# Changelog

## 1.2.3 — 2026-07-20

- The shipped entry.
EOF
printf '%s\n' "### Changed" >"$TMP/fragments-dangling-group/changelog.d/115.md"
check "fragment mode refuses a dangling fragment heading" 1 \
  "fragment 'changelog.d/115.md' has no entries" \
  in_tree fragments-dangling-group

fragment_tree fragments-bare-stamped 1.2.3 <<'EOF'
# Changelog

## 1.2.3 — 2026-07-20

- The shipped entry.

## 1.2.2 — 2026-07-01

- The older entry.
EOF
check "fragment bare + stamped section + consumed directory passes" 0 \
  "fragment mode" in_tree fragments-bare-stamped

cp -R "$TMP/fragments-bare-stamped" "$TMP/fragments-bare-survivor"
printf '%s\n' "- This entry was not consumed." \
  >"$TMP/fragments-bare-survivor/changelog.d/115.md"
check "fragment bare refuses and lists surviving fragments" 1 \
  "these fragments were not consumed: changelog.d/115.md" \
  in_tree fragments-bare-survivor

fragment_tree fragments-bare-wrong 1.2.3 <<'EOF'
# Changelog

## 9.9.9 — 2026-07-20

- The wrong release.

## 1.2.3 — 2026-07-19

- The right release was not stamped on top.
EOF
check "fragment bare refuses a stamp for another version" 1 \
  "stamped the wrong number" in_tree fragments-bare-wrong

fragment_tree fragments-bare-missing 1.2.3 <<'EOF'
# Changelog

## 1.2.2 — 2026-07-01

- The older entry.
EOF
check "fragment bare refuses a missing stamp via section diagnosis" 1 \
  "no section for '1.2.3'" in_tree fragments-bare-missing

fragment_tree fragments-cross-mode 1.2.4-dev <<'EOF'
# Changelog

## 1.2.3 — 2026-07-20

- The shipped entry.
EOF
check "same changelog passes in fragment mode" 0 "fragment mode" \
  in_tree fragments-cross-mode
rm -rf "$TMP/fragments-cross-mode/changelog.d"
check "same changelog fails in legacy mode" 1 "development tree" \
  in_tree fragments-cross-mode

# --- the action's wiring: inputs arrive as env vars --------------------------

mkdir -p "$TMP/env-tree"
printf '1.2.4-dev\n' >"$TMP/env-tree/VERSION"
printf '# Changelog\n\n## Unreleased\n\n- Pending.\n' >"$TMP/env-tree/NOTES.md"
# A non-default changelog name proves the env var is honored, not the default.
env_tree() {
  (cd "$TMP/env-tree" && CHANGELOG=NOTES.md VERSION_SOURCE=file bash "$SCRIPT")
}
check "env vars drive the script the way action.yml does" 0 "agrees" env_tree

mkdir -p "$TMP/env-fragments/custom.d"
printf '1.2.4-dev\n' >"$TMP/env-fragments/VERSION"
printf '# Changelog\n\n## 1.2.3 — 2026-07-20\n\n- Shipped.\n' \
  >"$TMP/env-fragments/CHANGELOG.md"
printf '%s\n' "# Changelog fragments" >"$TMP/env-fragments/custom.d/README.md"
env_fragments() {
  (cd "$TMP/env-fragments" && FRAGMENTS_DIR=custom.d bash "$SCRIPT")
}
check "fragments-dir env var selects fragment mode" 0 "fragment mode" env_fragments

summary
