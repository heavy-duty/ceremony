#!/usr/bin/env bash
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=test/harness.sh
source "$ROOT/test/harness.sh"
# shellcheck source=lib/changelog.sh
source "$ROOT/lib/changelog.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FIXTURE="$TMP/CHANGELOG.md"
cat >"$FIXTURE" <<'EOF'
# Changelog

Preamble prose belongs to no section.

## Unreleased

- Not yet released and never part of a version.

## 0.7.0 — 2026-07-20

### Added

- The seven-oh entry.

## 0.7.0-rc1 — 2026-07-19

- The release-candidate entry.

## 0.6.0 — 2026-07-18

- The six-oh entry.

## 0.5.0 — 2026-07-15

## 0.4.0
- A date-less version heading also parses.
EOF

assert_section() {
  local version="$1" expected="$2" actual
  actual="$(changelog_section "$FIXTURE" "$version")"
  [ "$actual" = "$expected" ] || {
    printf 'wanted:\n%s\ngot:\n%s\n' "$expected" "$actual"
    return 1
  }
}

check "extracts one section body exactly" 0 "" assert_section 0.7.0 $'### Added\n\n- The seven-oh entry.'
check "adjacent older section does not bleed" 0 "" assert_section 0.6.0 '- The six-oh entry.'
check "whole match selects the rc section" 0 "" assert_section 0.7.0-rc1 '- The release-candidate entry.'
check "Unreleased parses as a date-less heading" 0 "" assert_section Unreleased '- Not yet released and never part of a version.'
check "date-less version heading parses" 0 "" assert_section 0.4.0 '- A date-less version heading also parses.'
check "empty stamped section returns empty output" 0 "" assert_section 0.5.0 ""
check "missing section returns empty output" 0 "" assert_section 9.9.9 ""

PROBLEM_FIXTURE="$TMP/CHANGELOG.problems.md"
assert_problem() {
  local version="$1" expected_status="$2" expected="$3"
  check "predicate: $version / $expected" "$expected_status" "$expected" \
    changelog_section_problem "$PROBLEM_FIXTURE" "$version"
}

cat >"$PROBLEM_FIXTURE" <<'EOF'
# Changelog

## Unreleased

### Added

### Changed

### Fixed

## 1.0.0

- Flat dash entry.

## 1.1.0

* Flat star entry.

## 1.2.0

### Fixed

- Fixed entry.

## 1.3.0

### Added

- Added entry.

### Changed

* Changed entry.

### Fixed

- Fixed entry.

## 1.4.0

## 1.5.0

### Added

## 1.6.0

### Added

### Fixed

- Fixed entry.
EOF

assert_problem Unreleased 0 ""
assert_problem 1.0.0 0 ""
assert_problem 1.1.0 0 ""
assert_problem 1.2.0 0 ""
assert_problem 1.3.0 0 ""
assert_problem 1.4.0 1 "section '1.4.0' has no entries — a heading is not an entry"
assert_problem 1.5.0 1 "section '1.5.0' has no entries — a heading is not an entry"
assert_problem 1.6.0 1 "section '1.6.0' has an empty heading: '### Added'"
assert_problem 9.9.9 1 "no section for '9.9.9'"

MISSING_UNRELEASED_FIXTURE="$TMP/CHANGELOG.missing-unreleased.md"
cat >"$MISSING_UNRELEASED_FIXTURE" <<'EOF'
# Changelog

## 1.0.0

- Released entry.
EOF
check "predicate: absent Unreleased still refuses" 1 "no section for 'Unreleased'" \
  changelog_section_problem "$MISSING_UNRELEASED_FIXTURE" Unreleased

WRAPPER="$ROOT/bin/changelog-section"
check "wrapper publishes the requested body" 0 "The seven-oh entry" "$WRAPPER" 0.7.0 "$FIXTURE"
check "wrapper refuses an empty section" 1 "no section for '0.5.0'" "$WRAPPER" 0.5.0 "$FIXTURE"
check "wrapper refuses an absent section" 1 "no section for '9.9.9'" "$WRAPPER" 9.9.9 "$FIXTURE"
check "wrapper explains how the release PR fixes refusal" 1 "assembles the section" "$WRAPPER" 9.9.9 "$FIXTURE"
check "wrapper refuses a heading-only version section" 1 \
  "section '1.5.0' has no entries — a heading is not an entry" \
  "$WRAPPER" 1.5.0 "$PROBLEM_FIXTURE"
check "wrapper names the first dangling heading" 1 \
  "section '1.6.0' has an empty heading: '### Added'" \
  "$WRAPPER" 1.6.0 "$PROBLEM_FIXTURE"
check "wrapper prints seeded empty Unreleased without refusing" 0 "### Added" \
  "$WRAPPER" Unreleased "$PROBLEM_FIXTURE"
check "wrapper requires a version" 2 "usage:" "$WRAPPER"
check "wrapper refuses a missing file" 1 "no such file" "$WRAPPER" 1.0.0 "$TMP/missing.md"

mkdir "$TMP/default-file"
cp "$FIXTURE" "$TMP/default-file/CHANGELOG.md"
# The child shell, not this one, expands its positional parameters.
# shellcheck disable=SC2016
check "version alone reads the default changelog" 0 "The seven-oh entry" \
  bash -c 'cd "$1" && "$2" "$3"' _ "$TMP/default-file" "$WRAPPER" 0.7.0

REALISTIC="$ROOT/test/fixtures/CHANGELOG.realistic.md"
check "realistic changelog keeps its production heading shape" 0 "A mint records its provenance" \
  "$WRAPPER" 0.9.0 "$REALISTIC"
check "realistic adjacent release remains independently extractable" 0 "Merging the release PR" \
  "$WRAPPER" 0.8.0 "$REALISTIC"

# --- the fragment reader (#114) ----------------------------------------------

FRAG="$TMP/frags"
mkdir -p "$FRAG"

check "fragments: absent directory is empty output, not an error" 0 "" \
  changelog_fragments "$TMP/no-such-dir"
check "fragments: fragment-free directory is empty output, not an error" 0 "" \
  changelog_fragments "$FRAG"

printf 'marker\n' >"$FRAG/README.md"
check "fragments: README.md is the directory marker, never a fragment" 0 "" \
  changelog_fragments "$FRAG"

printf -- '- Two.\n' >"$FRAG/2.md"
printf -- '- Nine.\n' >"$FRAG/9.md"
printf -- '- Ten.\n' >"$FRAG/10.md"
printf -- '- Cross.\n' >"$FRAG/ceremony-14.md"
printf -- '- Local fourteen.\n' >"$FRAG/14.md"

assert_fragments_order() {
  local expected="$1" actual
  actual="$(changelog_fragments "$FRAG" | awk -F/ '{ print $NF }' | tr '\n' ' ')"
  actual="${actual% }"
  [ "$actual" = "$expected" ] || {
    printf 'wanted: %s\ngot: %s\n' "$expected" "$actual"
    return 1
  }
}
check "fragments: issue number descending (numeric, 10 before 9), filename tie-break" 0 "" \
  assert_fragments_order "14.md ceremony-14.md 10.md 9.md 2.md"

# --- the fragment predicate (#114) -------------------------------------------

PF="$TMP/frag-problems"
mkdir -p "$PF"

printf -- '- Fine.\n' >"$PF/7.md"
check "fragment predicate: a flat fragment passes" 0 "" \
  changelog_fragment_problem "$PF/7.md"

cat >"$PF/8.md" <<'EOF'
### Added

- Grouped fine.
EOF
check "fragment predicate: a grouped fragment passes" 0 "" \
  changelog_fragment_problem "$PF/8.md"

printf -- '- Cross-repo.\n' >"$PF/ceremony-14.md"
check "fragment predicate: a cross-repo name passes" 0 "" \
  changelog_fragment_problem "$PF/ceremony-14.md"

printf -- '- Bad name.\n' >"$PF/Fix-12.md"
check "fragment predicate: an uppercase prefix is refused, file named" 1 "Fix-12.md" \
  changelog_fragment_problem "$PF/Fix-12.md"
printf -- '- Bad name.\n' >"$PF/notes.txt"
check "fragment predicate: a non-.md file is refused, file named" 1 "notes.txt" \
  changelog_fragment_problem "$PF/notes.txt"
printf -- '- Bad name.\n' >"$PF/12.markdown"
check "fragment predicate: .markdown is refused, file named" 1 "12.markdown" \
  changelog_fragment_problem "$PF/12.markdown"
printf -- '- No number.\n' >"$PF/notes.md"
check "fragment predicate: a name with no trailing issue number is refused" 1 "notes.md" \
  changelog_fragment_problem "$PF/notes.md"

cat >"$PF/20.md" <<'EOF'
## 1.0.0 — 2026-07-24

- Smuggled heading.
EOF
check "fragment predicate: a '## ' line is refused — the heading is the assembler's" 1 \
  "the section heading is the assembler's to write" \
  changelog_fragment_problem "$PF/20.md"

printf '### Added\n' >"$PF/21.md"
check "fragment predicate: no bullet anywhere is refused" 1 \
  "has no entries — a heading is not an entry" \
  changelog_fragment_problem "$PF/21.md"

cat >"$PF/22.md" <<'EOF'
### Added

### Fixed

- Fixed entry.
EOF
check "fragment predicate: a dangling grouped heading is refused, heading named" 1 \
  "has an empty heading: '### Added'" \
  changelog_fragment_problem "$PF/22.md"

entry_of_length() {
  local count="$1"
  awk -v count="$count" 'BEGIN {
    printf "%0*d\n", count, 0
  }'
}

printf -- '- %s\n' "$(entry_of_length 300)" >"$PF/23.md"
check "fragment predicate: a 300-character entry passes" 0 "" \
  changelog_fragment_problem "$PF/23.md"

printf -- '- %s\n' "$(entry_of_length 301)" >"$PF/24.md"
check "fragment predicate: a 301-character entry is refused with actionable detail" 1 \
  "301 characters, bound 300 — split it into multiple '- ' entries in this same fragment" \
  changelog_fragment_problem "$PF/24.md"
check "fragment predicate: an overlong diagnosis previews the entry" 1 \
  "000000000000000000000000000000000000000000000000000000000000…" \
  changelog_fragment_problem "$PF/24.md"

{
  printf -- '- %s\n' "$(entry_of_length 200)"
  printf -- '- %s\n' "$(entry_of_length 200)"
} >"$PF/25.md"
check "fragment predicate: several bounded entries may total over 300 characters" 0 "" \
  changelog_fragment_problem "$PF/25.md"

{
  printf -- '- %s\n' "$(entry_of_length 60)"
  printf '  %s\n' "$(entry_of_length 60)"
  printf '  %s\n' "$(entry_of_length 60)"
  printf '  %s\n' "$(entry_of_length 67)"
} >"$PF/26.md"
check "fragment predicate: a roughly 250-character entry may wrap over four lines" 0 "" \
  changelog_fragment_problem "$PF/26.md"

{
  printf '### Added\n\n'
  printf -- '- %s\n\n' "$(entry_of_length 300)"
  printf '### Fixed\n\n'
  printf -- '* %s\n' "$(entry_of_length 301)"
} >"$PF/27.md"
check "fragment predicate: grouped headings are not counted and grouped bullets are bounded" 1 \
  "301 characters, bound 300" \
  changelog_fragment_problem "$PF/27.md"

check "section predicate: published over-bound entries remain unvalidated" 0 "" \
  changelog_section_problem "$ROOT/CHANGELOG.md" 0.3.0

# --- the assembler (#114) ----------------------------------------------------

assert_assemble() {
  local dir="$1" expected="$2" actual
  actual="$(changelog_assemble "$dir")"
  [ "$actual" = "$expected" ] || {
    printf 'wanted:\n%s\ngot:\n%s\n' "$expected" "$actual"
    return 1
  }
}

AF="$TMP/assemble-flat"
mkdir -p "$AF"
printf 'marker\n' >"$AF/README.md"
cat >"$AF/3.md" <<'EOF'
- Three — an em dash, and prose that
  wraps onto a continuation line.
EOF
printf -- '- Ten.\n- Ten again.\n' >"$AF/10.md"
check "assemble: flat fragments, newest issue first, prose verbatim" 0 "" \
  assert_assemble "$AF" $'- Ten.\n- Ten again.\n- Three — an em dash, and prose that\n  wraps onto a continuation line.'

check "assemble: an empty directory is empty output — refusing is the caller's stance" 0 "" \
  changelog_assemble "$TMP/no-such-dir"

AG="$TMP/assemble-grouped"
mkdir -p "$AG"
cat >"$AG/21.md" <<'EOF'
### Fixed

- Fixed twenty-one.
EOF
cat >"$AG/20.md" <<'EOF'
### Added

- Added twenty.

### Docs

- Docs twenty.
EOF
cat >"$AG/19.md" <<'EOF'
### Security

- Security nineteen.

### Added

- Added nineteen.
EOF
check "assemble: canonical group order, unnamed group appended, fragment order inside a group" 0 "" \
  assert_assemble "$AG" $'### Added\n\n- Added twenty.\n- Added nineteen.\n\n### Fixed\n\n- Fixed twenty-one.\n\n### Security\n\n- Security nineteen.\n\n### Docs\n\n- Docs twenty.'

AM="$TMP/assemble-mixed"
mkdir -p "$AM"
printf -- '- Flat five.\n' >"$AM/5.md"
cat >"$AM/6.md" <<'EOF'
### Added

- Grouped six.
EOF
check "assemble: mixed shapes refused, grouped side named" 1 "6.md" \
  changelog_assemble "$AM"
check "assemble: mixed shapes refused, flat side named too" 1 "5.md" \
  changelog_assemble "$AM"

AX="$TMP/assemble-selfmixed"
mkdir -p "$AX"
cat >"$AX/7.md" <<'EOF'
- Ungrouped lead.

### Added

- Grouped follow.
EOF
check "assemble: one fragment mixing both shapes is refused, file named" 1 \
  "'$AX/7.md' mixes grouped headings and ungrouped bullets" \
  changelog_assemble "$AX"

# --- the fragment-set shape predicate (#159) ---------------------------------

SHAPE_CHANGELOG="$TMP/CHANGELOG.shape.md"
SHAPE_DIR="$TMP/shape-fragments"
mkdir -p "$SHAPE_DIR"

cat >"$SHAPE_CHANGELOG" <<'EOF'
# Changelog

## 2.0.0 — 2026-07-24

- Newest section is flat.

## 1.0.0 — 2026-07-01

### Fixed

- Older section is grouped.
EOF
printf -- '- Flat fragment.\n' >"$SHAPE_DIR/1.md"
check "shape: flat set matches newest flat published section" 0 "" \
  changelog_shape_problem "$SHAPE_CHANGELOG" "$SHAPE_DIR"

cat >"$SHAPE_DIR/1.md" <<'EOF'
### Fixed

- Grouped fragment.
EOF
check "shape: grouped set names its conflict with newest flat published section" 1 \
  "fragment '$SHAPE_DIR/1.md' is grouped but newest published section '2.0.0' in '$SHAPE_CHANGELOG' is flat" \
  changelog_shape_problem "$SHAPE_CHANGELOG" "$SHAPE_DIR"

cat >"$SHAPE_CHANGELOG" <<'EOF'
# Changelog

## 2.0.0 — 2026-07-24

### Fixed

- Newest section is grouped.
EOF
printf -- '- Flat fragment.\n' >"$SHAPE_DIR/1.md"
check "shape: flat set names its conflict with newest grouped published section" 1 \
  "fragment '$SHAPE_DIR/1.md' is flat but newest published section '2.0.0' in '$SHAPE_CHANGELOG' is grouped" \
  changelog_shape_problem "$SHAPE_CHANGELOG" "$SHAPE_DIR"

cat >"$SHAPE_DIR/1.md" <<'EOF'
### Fixed

- Grouped fragment.
EOF
check "shape: grouped set matches newest grouped published section" 0 "" \
  changelog_shape_problem "$SHAPE_CHANGELOG" "$SHAPE_DIR"
check "shape: consistent set with no published section passes" 0 "" \
  changelog_shape_problem "$TMP/no-such-changelog" "$SHAPE_DIR"
rm "$SHAPE_DIR/1.md"
check "shape: empty fragment set makes the anchor rule vacuous" 0 "" \
  changelog_shape_problem "$SHAPE_CHANGELOG" "$SHAPE_DIR"

summary
