#!/usr/bin/env bash
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=test/harness.sh
source "$ROOT/test/harness.sh"
# shellcheck source=actions/labels-scope/labels-scope.sh
source "$ROOT/actions/labels-scope/labels-scope.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

TAB="$(printf '\t')"

# --- glob_to_regex: the minimatch subset the family actually uses ------------

check "glob: ** crosses slashes" 0 '^lib/.*$' glob_to_regex 'lib/**'
check "glob: * stays inside a segment" 0 '^[^/]*\.md$' glob_to_regex '*.md'
check "glob: ? is one non-slash char" 0 '^doc[^/]/x$' glob_to_regex 'doc?/x'
check "glob: literal path is anchored whole" 0 '^README$' glob_to_regex 'README'
check "glob: dots are escaped, not wildcards" 0 \
  '^commands/users-[^/]*\.sh$' glob_to_regex 'commands/users-*.sh'
check "glob: regex specials are literal" 0 '^a\+b\{c\}\(d\)$' glob_to_regex 'a+b{c}(d)'

# --- derive_labels: pure matching over parsed rows ---------------------------

cfg="scope:release-flow${TAB}lib/**
scope:release-flow${TAB}VERSION
scope:docs${TAB}docs/**
scope:docs${TAB}README"

check "derive: ** matches nested paths" 0 "scope:release-flow" \
  derive_labels "$cfg" 'lib/deep/facts.sh'
# shellcheck disable=SC2016 # expansion belongs to the nested bash
check "derive: ** does not match the bare directory" 1 "" \
  bash -c 'source "$1"; [ -n "$(derive_labels "$2" lib)" ]' _ \
  "$ROOT/actions/labels-scope/labels-scope.sh" "$cfg"
# shellcheck disable=SC2016 # expansion belongs to the nested bash
check "derive: literal glob does not match a nested twin" 1 "" \
  bash -c 'source "$1"; [ -n "$(derive_labels "$2" docs2/README)" ]' _ \
  "$ROOT/actions/labels-scope/labels-scope.sh" "$cfg"
# shellcheck disable=SC2016 # expansion belongs to the nested bash
check "derive: one label per line, config order, deduped" 0 "" \
  bash -c 'source "$1"; got="$(derive_labels "$2" "$(printf "%s\n" README VERSION lib/x docs/a.md)")"
    [ "$got" = "$(printf "%s\n" scope:release-flow scope:docs)" ] || { printf "%s\n" "$got"; exit 1; }' _ \
  "$ROOT/actions/labels-scope/labels-scope.sh" "$cfg"
check "derive: no files derives nothing" 0 "" derive_labels "$cfg" ""
check "derive: unmatched files derive nothing" 0 "" derive_labels "$cfg" 'src/other.c'

# --- parse_labeler_config: every spelling the governed repos use -------------
# Needs yq (preinstalled on ubuntu-latest). Locally, skip with a notice so
# the suite stays runnable in minimal environments; in CI the skip is a
# failure — ci.yml sets CEREMONY_REQUIRE_YQ so these cases can never
# quietly stop running there.

if command -v yq >/dev/null 2>&1; then
  parses() { parse_labeler_config <"$1"; }

  # block sequences + block glob list (ceremony's own spelling)
  cat >"$TMP/block.yml" <<'EOF'
# a comment, as ceremony's own file carries
scope:labels:
  - changed-files:
      - any-glob-to-any-file:
          - .github/workflows/labels.yml
          - actions/labels-reconcile/**
EOF
  check "parse: block style" 0 \
    "scope:labels${TAB}actions/labels-reconcile/**" parses "$TMP/block.yml"

  # quoted keys + flow glob list (box/rig's spelling)
  cat >"$TMP/flow.yml" <<'EOF'
"scope:cli":
  - changed-files:
      - any-glob-to-any-file: ["bin/**", "test/cli.sh"]
EOF
  check "parse: quoted key, flow list" 0 \
    "scope:cli${TAB}bin/**" parses "$TMP/flow.yml"

  # flow map inside changed-files (incubator's spelling)
  cat >"$TMP/flowmap.yml" <<'EOF'
"scope:core":
  - changed-files: [{any-glob-to-any-file: ["apps/core/**"]}]
EOF
  check "parse: flow map entry" 0 \
    "scope:core${TAB}apps/core/**" parses "$TMP/flowmap.yml"

  # a single glob as a bare string
  cat >"$TMP/single.yml" <<'EOF'
scope:docs:
  - changed-files:
      - any-glob-to-any-file: docs/**
EOF
  check "parse: bare-string glob" 0 \
    "scope:docs${TAB}docs/**" parses "$TMP/single.yml"

  # the repo's real mapping parses, and rows keep config order
  check "parse: ceremony's own labeler.yml" 0 \
    "scope:labels${TAB}.github/labeler.yml" parses "$ROOT/.github/labeler.yml"

  # refusals: unsupported shapes fail loudly, naming the label
  cat >"$TMP/allglobs.yml" <<'EOF'
scope:x:
  - changed-files:
      - all-globs-to-all-files: ["a/**"]
EOF
  check "parse: all-globs-to-all-files is refused" 5 \
    "scope:x: unsupported matcher(s) all-globs-to-all-files" parses "$TMP/allglobs.yml"

  cat >"$TMP/branch.yml" <<'EOF'
scope:x:
  - head-branch: ["^feature/"]
EOF
  check "parse: branch matchers are refused" 5 \
    "scope:x: unsupported key(s) head-branch" parses "$TMP/branch.yml"

  cat >"$TMP/toplist.yml" <<'EOF'
- scope:x
EOF
  check "parse: non-map top level is refused" 5 \
    "top level must be a map" parses "$TMP/toplist.yml"

  cat >"$TMP/backslash.yml" <<'EOF'
scope:x:
  - changed-files:
      - any-glob-to-any-file: ["a\\b/**"]
EOF
  check "parse: backslash escapes are refused" 5 \
    "backslash in glob" parses "$TMP/backslash.yml"
elif [ -n "${CEREMONY_REQUIRE_YQ:-}" ]; then
  echo "FAIL: CEREMONY_REQUIRE_YQ is set but yq is missing — the config parse cases did not run"
  FAIL=$((FAIL + 1))
else
  echo "SKIP: yq not found — parse_labeler_config cases not exercised"
fi

summary
