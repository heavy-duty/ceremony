#!/usr/bin/env bash
# Contract tests for .github/scripts/self-ref-check.sh (issue #9; #1 D3) —
# the pin rules, driven against constructed fixture trees. The CI step runs
# the same script against the real tree. set -u, not -e: failing commands
# are behavior for the harness to inspect.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=test/harness.sh
. "$ROOT/test/harness.sh"

CHECK="$ROOT/.github/scripts/self-ref-check.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# tree <name> <pin...> — a fixture tree whose workflows carry the pins (one
# workflow file per pin, mimicking release.yml + labels.yml).
tree() {
  local name="$1"
  shift
  mkdir -p "$TMP/$name/.github/workflows"
  local i=0 pin
  for pin in "$@"; do
    i=$((i + 1))
    printf 'name: w%s\nenv:\n  CEREMONY_SELF_REF: "%s"\n' "$i" "$pin" \
      >"$TMP/$name/.github/workflows/w$i.yml"
  done
}

run_check() {
  bash "$CHECK" "$TMP/$1"
}

# --- the pre-dogfood window (no VERSION yet — the tree #9 lands on) ---------

tree pre-dogfood 0.1.0
check "no VERSION: pin unchecked, loud notice, green" 0 "cannot bind yet" \
  run_check pre-dogfood

# --- a bare tree: pin must equal VERSION -------------------------------------

tree bare-good 0.3.0
printf '0.3.0\n' >"$TMP/bare-good/VERSION"
check "bare tree, pin == VERSION passes" 0 "agrees" run_check bare-good

tree bare-stale 0.2.0
printf '0.3.0\n' >"$TMP/bare-stale/VERSION"
check "bare tree, stale pin fails" 1 "must be '0.3.0'" run_check bare-stale

# --- a -dev tree: pin must equal the newest stamped heading ------------------

tree dev-good 0.3.0
printf '0.4.0-dev\n' >"$TMP/dev-good/VERSION"
cat >"$TMP/dev-good/CHANGELOG.md" <<'EOF'
# Changelog

## Unreleased

- Pending entry.

## 0.3.0 — 2026-07-20

- The shipped entry.

## 0.2.0 — 2026-07-01

- Older entry.
EOF
check "-dev tree, pin == newest stamped heading passes" 0 "agrees" \
  run_check dev-good

tree dev-stale 0.2.0
printf '0.4.0-dev\n' >"$TMP/dev-stale/VERSION"
cp "$TMP/dev-good/CHANGELOG.md" "$TMP/dev-stale/CHANGELOG.md"
check "-dev tree, pin behind the last release fails" 1 "must be '0.3.0'" \
  run_check dev-stale

# Whole-field match: an rc heading never satisfies the bare X.Y.Z shape —
# the newest BARE heading below it is the last release.
tree dev-rc 0.3.0
printf '0.4.0-dev\n' >"$TMP/dev-rc/VERSION"
cat >"$TMP/dev-rc/CHANGELOG.md" <<'EOF'
# Changelog

## Unreleased

## 0.4.0-rc1 — 2026-07-21

- The candidate's entry.

## 0.3.0 — 2026-07-20

- The shipped entry.
EOF
check "-dev tree: an rc heading is skipped, the bare one governs" 0 "agrees" \
  run_check dev-rc

# --- the pre-first-release tree: pin == VERSION with -dev stripped -----------

tree first-good 0.1.0
printf '0.1.0-dev\n' >"$TMP/first-good/VERSION"
printf '# Changelog\n\n## Unreleased\n\n- Everything so far.\n' \
  >"$TMP/first-good/CHANGELOG.md"
check "pre-first-release: pin == VERSION minus -dev passes" 0 "agrees" \
  run_check first-good

tree first-stale 0.0.1
printf '0.1.0-dev\n' >"$TMP/first-stale/VERSION"
check "pre-first-release: any other pin fails" 1 "must be '0.1.0'" \
  run_check first-stale

# --- degenerate trees --------------------------------------------------------

mkdir -p "$TMP/no-pin/.github/workflows"
printf 'name: w\non: push\n' >"$TMP/no-pin/.github/workflows/w.yml"
check "no pin anywhere fails — the guard must have something to guard" 1 \
  "nothing to guard" run_check no-pin

tree split-pin 0.3.0 0.2.0
printf '0.3.0\n' >"$TMP/split-pin/VERSION"
check "disagreeing pins across workflows fail" 1 "disagree" run_check split-pin

tree empty-version 0.1.0
: >"$TMP/empty-version/VERSION"
check "an empty VERSION fails loudly" 1 "is empty" run_check empty-version

# --- the real tree -----------------------------------------------------------

# Whatever state the repo is in (pre-dogfood today, versioned after #11),
# the guard must hold on it — this is the CI step's exact invocation.
real_check() {
  (cd "$ROOT" && bash "$CHECK")
}
check "the real tree passes its own guard" 0 "" real_check

summary
