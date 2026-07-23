#!/usr/bin/env bash
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=test/harness.sh
source "$ROOT/test/harness.sh"
# shellcheck source=actions/labels-reconcile/labels-reconcile.sh
source "$ROOT/actions/labels-reconcile/labels-reconcile.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

printf '%s\n' \
  'panel=one two three' \
  'triage-actors=triage-one' \
  '' \
  'scope:one|C5DEF5|First scope' \
  'scope:two|C5DEF5|Second scope' >"$TMP/good.conf"

check "config accepts panel, blanks, and scope rows" 0 "" load_config "$TMP/good.conf"
# shellcheck disable=SC2016 # expansion belongs to the nested bash
check "panel is parsed" 0 "one two three" bash -c \
  'source "$1"; load_config "$2"; printf "%s\n" "${BOTS[*]}"' _ \
  "$ROOT/actions/labels-reconcile/labels-reconcile.sh" "$TMP/good.conf"
# shellcheck disable=SC2016 # expansion belongs to the nested bash
check "core and config rows merge" 0 "scope:two|C5DEF5|Second scope" bash -c \
  'source "$1"; core_label_rows; configured_label_rows "$2"' _ \
  "$ROOT/actions/labels-reconcile/labels-reconcile.sh" "$TMP/good.conf"
attention_row='attention|D93F0B|A demand is parked here for the assignee: pick up the thread, ack by removing this label'
# shellcheck disable=SC2016 # expansion belongs to the nested bash
check "attention core row is emitted once, byte-exact" 0 "1" bash -c \
  'source "$1"; core_label_rows | grep -cxF "$2"' _ \
  "$ROOT/actions/labels-reconcile/labels-reconcile.sh" "$attention_row"
# shellcheck disable=SC2016 # fields are intentionally split in the nested shell
check "attention description survives label field splitting" 0 \
  "A demand is parked here for the assignee: pick up the thread, ack by removing this label" \
  bash -c 'source "$1"; while IFS="|" read -r name color desc; do
    [ "$name" != attention ] || printf "%s\n" "$desc"
  done < <(core_label_rows)' _ "$ROOT/actions/labels-reconcile/labels-reconcile.sh"
# shellcheck disable=SC2016 # expansion belongs to the nested bash
check "triage config is not parsed as a label row" 1 "" bash -c \
  'source "$1"; configured_label_rows "$2" | grep -F triage-actors' _ \
  "$ROOT/actions/labels-reconcile/labels-reconcile.sh" "$TMP/good.conf"
check "missing scope config is an empty table" 0 "" configured_label_rows "$TMP/missing.conf"

printf '%s\n' 'scope:bad|C5DEF5' >"$TMP/bad.conf"
check "wrong field count fails loudly" 1 "malformed label row" configured_label_rows "$TMP/bad.conf"
printf '%s\n' 'scope:bad|C5DEF5|description|with pipe' >"$TMP/pipe.conf"
check "pipe in description is explicitly refused" 1 "malformed label row" configured_label_rows "$TMP/pipe.conf"
printf '%s\n' 'scope:only|C5DEF5|No panel' >"$TMP/no-panel.conf"
check "missing panel fails loudly" 1 "missing panel= line" load_config "$TMP/no-panel.conf"
load_config "$TMP/good.conf"
set_required_bots two
check "PR author is recused from the required panel" 0 "one three" printf '%s\n' "${REQUIRED_BOTS[*]}"

summary
