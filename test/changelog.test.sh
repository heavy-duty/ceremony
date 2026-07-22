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

WRAPPER="$ROOT/bin/changelog-section"
check "wrapper publishes the requested body" 0 "The seven-oh entry" "$WRAPPER" "$FIXTURE" 0.7.0
check "wrapper refuses an empty section" 1 "no section for '0.5.0'" "$WRAPPER" "$FIXTURE" 0.5.0
check "wrapper refuses an absent section" 1 "no section for '9.9.9'" "$WRAPPER" "$FIXTURE" 9.9.9
check "wrapper explains how the release PR fixes refusal" 1 "stamps the Unreleased section" "$WRAPPER" "$FIXTURE" 9.9.9
check "wrapper requires both arguments" 2 "usage:" "$WRAPPER"
check "wrapper refuses a missing file" 1 "no such file" "$WRAPPER" "$TMP/missing.md" 1.0.0

REALISTIC="$ROOT/test/fixtures/CHANGELOG.realistic.md"
check "realistic changelog keeps its production heading shape" 0 "A mint records its provenance" \
  "$WRAPPER" "$REALISTIC" 0.9.0
check "realistic adjacent release remains independently extractable" 0 "Merging the release PR" \
  "$WRAPPER" "$REALISTIC" 0.8.0

summary
