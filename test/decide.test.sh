#!/usr/bin/env bash
# Contract tests for lib/decide.sh (issue #8) — every row of the decision
# table, offline. set -u, not -e: failing commands are behavior for the
# harness to inspect.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=test/harness.sh
. "$ROOT/test/harness.sh"

DECIDE="$ROOT/lib/decide.sh"

# decide <VER> <BASE_VER> <RELEASED> <LABELED> — run the script with exactly
# these four facts in its environment.
decide() {
  VER="$1" BASE_VER="$2" RELEASED="$3" LABELED="$4" bash "$DECIDE"
}

# decide_bare <VER> <BASE_VER> — RELEASED and LABELED genuinely unset, not
# empty: the -dev rows must not require them at all, so the workflow can
# skip API calls it doesn't need.
decide_bare() {
  env -u RELEASED -u LABELED VER="$1" BASE_VER="$2" bash "$DECIDE"
}

# refuses_cleanly <cmd...> — exit 1 AND no ceremony= line on stdout: a
# refusal dies creating nothing, not even an output line for the workflow
# to append.
refuses_cleanly() {
  local out
  out="$("$@" 2>/dev/null)"
  [ $? -eq 1 ] && ! printf '%s' "$out" | grep -q "ceremony="
}

# --- the six table rows ------------------------------------------------------

check "row 1: -dev unchanged -> ceremony=no" 0 "ceremony=no" \
  decide 1.2.3-dev 1.2.3-dev "" ""
check "row 1: notice names work under the label" 0 "work under the release label" \
  decide 1.2.3-dev 1.2.3-dev "" ""

check "row 2: -dev changed -> ceremony=no" 0 "ceremony=no" \
  decide 1.2.4-dev 1.2.3 "" ""
check "row 2: notice names the dev tree" 0 "a dev tree is by definition not a release" \
  decide 1.2.4-dev 1.2.3 "" ""

check "row 3: bare unchanged, released -> ceremony=no" 0 "ceremony=no" \
  decide 1.2.3 1.2.3 yes ""
check "row 3: notice names the post-release window" 0 "post-release window" \
  decide 1.2.3 1.2.3 yes ""

check "row 4: bare unchanged, unreleased -> refuse" 1 "did not mint the version" \
  decide 1.2.3 1.2.3 no ""
check "row 4: refusal carries the first-release edge parenthetical" 1 "drop the label" \
  decide 1.2.3 1.2.3 no ""
check "row 4: refusal creates nothing" 0 "" \
  refuses_cleanly decide 1.2.3 1.2.3 no ""

check "row 5: bare transition, unlabeled -> refuse" 1 "not a bare push" \
  decide 1.2.3 1.2.2 "" no
check "row 5: refusal creates nothing" 0 "" \
  refuses_cleanly decide 1.2.3 1.2.2 "" no

check "row 6: bare transition, labeled -> ceremony=yes" 0 "ceremony=yes" \
  decide 1.2.3 1.2.3-dev "" yes

# --- fact validation (before the table) --------------------------------------

check "empty VER refused" 1 "VER is empty" decide "" 1.2.3 yes yes
check "empty BASE_VER refused" 1 "BASE_VER is empty" decide 1.2.3 "" yes yes
check "garbage RELEASED refused" 1 "expected yes, no, or empty" \
  decide 1.2.3 1.2.3 maybe ""
check "garbage LABELED refused" 1 "expected yes, no, or empty" \
  decide 1.2.3 1.2.2 "" true

# --- facts not consulted must not be required --------------------------------

check "row 1 with RELEASED/LABELED unset" 0 "ceremony=no" \
  decide_bare 1.2.3-dev 1.2.3-dev
check "row 2 with RELEASED/LABELED unset" 0 "ceremony=no" \
  decide_bare 1.2.4-dev 1.2.3-dev

# --- facts consulted must not fall through to "no" ---------------------------

check "bare unchanged with empty RELEASED refused" 1 "RELEASED is empty" \
  decide 1.2.3 1.2.3 "" ""
check "bare transition with empty LABELED refused" 1 "LABELED is empty" \
  decide 1.2.3 1.2.2 "" ""

# --- rc versions behave as bare (only -dev is special-cased) -----------------

check "rc transition with a label is a shippable ceremony" 0 "ceremony=yes" \
  decide 1.2.3-rc1 1.2.3-dev "" yes
check "rc unchanged and released is the post-release window" 0 "ceremony=no" \
  decide 1.2.3-rc1 1.2.3-rc1 yes ""

# --- purity: no git, no gh, no network (issue #8 acceptance) -----------------

# no_tool_calls — outside comments, the script never invokes git, gh, or a
# network client; the decision stays provable offline.
no_tool_calls() {
  ! grep -v '^[[:space:]]*#' "$DECIDE" | grep -Ewq 'git|gh|curl|wget'
}
check "decide.sh calls no git/gh/network tools" 0 "" no_tool_calls

summary
