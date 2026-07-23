#!/usr/bin/env bash
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=test/harness.sh
source "$ROOT/test/harness.sh"
# shellcheck source=actions/issueflow-reconcile/issueflow-reconcile.sh
source "$ROOT/actions/issueflow-reconcile/issueflow-reconcile.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

printf '%s\n' \
  'panel=one two' \
  'triage-actors=triage-one triage-two' \
  'scope:one|C5DEF5|First scope' >"$TMP/good.conf"
check "triage actors parse beside panel and labels" 0 "" load_issueflow_config "$TMP/good.conf"
load_issueflow_config "$TMP/good.conf"
check "triage actor is recognized" 0 "" is_triage_actor triage-two
check "non-triage actor is rejected" 1 "" is_triage_actor builder
printf '%s\n' 'panel=one' >"$TMP/missing.conf"
check "missing triage actors fails loudly" 1 "missing triage-actors=" load_issueflow_config "$TMP/missing.conf"
printf '%s\n' 'triage-actors=one' 'triage-actors=two' >"$TMP/duplicate.conf"
check "duplicate triage actors fails loudly" 1 "duplicate triage-actors" load_issueflow_config "$TMP/duplicate.conf"

# The dogfood caller and reusable workflow must expose the same runtime facts
# as the documented consumer stub. Static pins catch YAML blocks drifting to
# the adjacent composite step, which otherwise fails only after merge.
check "dogfood caller wakes on issue events" 0 "  issues:" \
  grep -F "  issues:" "$ROOT/.github/workflows/self-labels.yml"
dogfood_pr_step="$(sed -n \
  '/name: reconcile state + stale (dogfood/,/name: reconcile issue flow/p' \
  "$ROOT/.github/workflows/labels.yml")"
# shellcheck disable=SC2016 # GitHub expressions are asserted as literals
check "dogfood PR reconcile receives repository" 0 '          REPO: ${{ github.repository }}' \
  grep -F '          REPO: ${{ github.repository }}' <<<"$dogfood_pr_step"
# shellcheck disable=SC2016 # GitHub expressions are asserted as literals
check "dogfood PR reconcile receives token" 0 '          GH_TOKEN: ${{ github.token }}' \
  grep -F '          GH_TOKEN: ${{ github.token }}' <<<"$dogfood_pr_step"

# Invariant 1: exactly one queue category.
check "one ready queue label is valid" 0 "KEEP" queue_decision <<<"ready"
check "zero queue labels is derivably needs-triage" 0 "ADD_NEEDS_TRIAGE" queue_decision <<<"enhancement"
check "multiple queue labels are ambiguous" 0 "FLAG_CONFLICT" queue_decision <<< $'ready\nblocked'
check "needs-triage plus queue is a conflict" 0 "FLAG_CONFLICT" queue_decision <<< $'needs-triage\nready'

# Invariant 2: claims have an owner and either a PR or recent activity.
check "claim with open PR stays claimed" 0 "KEEP" claim_decision 1 true 999999
check "unassigned claim is flagged" 0 "FLAG_UNASSIGNED" claim_decision 0 false 60
check "quiet unassigned claim is also reclaimed" 0 "RECLAIM" claim_decision 0 false $((STALE_AFTER + 1))
# shellcheck disable=SC2016 # expansions belong to the isolated bash -c process
check "injected clock: below stale boundary stays claimed" 0 "KEEP" \
  bash -c 'ISSUEFLOW_NOW=100000 ISSUEFLOW_STALE_HOURS=1 source "$1"; claim_decision_at 1 false 96401' _ \
  "$ROOT/actions/issueflow-reconcile/issueflow-reconcile.sh"
# shellcheck disable=SC2016 # expansions belong to the isolated bash -c process
check "injected clock: exact stale boundary stays claimed" 0 "KEEP" \
  bash -c 'ISSUEFLOW_NOW=100000 ISSUEFLOW_STALE_HOURS=1 source "$1"; claim_decision_at 1 false 96400' _ \
  "$ROOT/actions/issueflow-reconcile/issueflow-reconcile.sh"
# shellcheck disable=SC2016 # expansions belong to the isolated bash -c process
check "injected clock: past stale boundary is reclaimed" 0 "RECLAIM" \
  bash -c 'ISSUEFLOW_NOW=100000 ISSUEFLOW_STALE_HOURS=1 source "$1"; claim_decision_at 1 false 96399' _ \
  "$ROOT/actions/issueflow-reconcile/issueflow-reconcile.sh"
# shellcheck disable=SC2016 # expansion belongs to the isolated bash -c process
check "invalid injected clock fails loudly" 1 "ISSUEFLOW_NOW must be UTC epoch seconds" \
  bash -c 'ISSUEFLOW_NOW=garbage source "$1"' _ \
  "$ROOT/actions/issueflow-reconcile/issueflow-reconcile.sh"
check "reclaim marker is stable within a claim episode" 0 "claim-reclaimed-96399" \
  claim_reclaim_marker 96399
check "a later claim episode receives a new reclaim marker" 0 "claim-reclaimed-99999" \
  claim_reclaim_marker 99999

# Invariant 3: blocked declarations parse and release only when all close.
refs="$(blocked_references <<< $'Context #99. Blocked by #12 (first), #7 (second). Blocks #44.')"
check "blocked declaration extracts only declared refs" 0 $'7\n12' printf '%s\n' "$refs"
body=$'Blocked by #12 (first),\n#7 (soft-wrapped second). Blocks #44.'
check "soft-wrapped blocker declaration retains continuation refs" 0 "" test \
  "$(blocked_references <<<"$body")" = $'7\n12'
body=$'Blocked by #12 (known)\nFollow-up context mentions #7 without a sentence boundary'
check "unterminated blocker prose errs toward retaining dependencies" 0 "" test \
  "$(blocked_references <<<"$body")" = $'7\n12'
body="Part of #1. Blocked by #11 (needs a ceremony tag to pin), #12 (must be executed from the guide), #19 (the conversion vendors the doctrine). Blocks #14, #15 (they inherit the pilot's lessons)."
check "real issue 13 inline blockers parse" 0 "" test \
  "$(blocked_references <<<"$body")" = $'11\n12\n19'
body="Part of #1. Blocked by #13 (inherits the pilot's lessons). Can run in parallel with #15."
check "real issue 14 inline blocker parses" 0 "" test \
  "$(blocked_references <<<"$body")" = "13"
body="Part of #1. Blocked by #13 (pilot lessons). Can run in parallel with #14."
check "real issue 15 inline blocker parses" 0 "" test \
  "$(blocked_references <<<"$body")" = "13"
body="Part of #1. Blocked by #11, #12 (needs a released ceremony + the bootstrap guide); benefits from #13's lessons but does not need #14/#15."
check "real issue 16 inline blockers parse" 0 "" test \
  "$(blocked_references <<<"$body")" = $'11\n12'
check "open blocker keeps issue blocked" 0 "KEEP" blocked_decision "$refs" $'CLOSED\nOPEN'
check "all closed blockers release issue" 0 "READY" blocked_decision "$refs" $'CLOSED\nCLOSED'
check "missing blocked declaration is flagged" 0 "FLAG_UNPARSEABLE" blocked_decision "" ""
check "unreadable blocker is flagged" 0 "FLAG_UNPARSEABLE" blocked_decision "12" "UNKNOWN"

# Invariant 4: only configured triage actors mint directly into the queue.
check "triage-authored ready issue is accepted" 0 "KEEP" author_decision true <<<"ready"
check "outside author receives needs-triage" 0 "ADD_NEEDS_TRIAGE" author_decision false <<<"ready"
check "outside author already marked needs-triage is stable" 0 "KEEP" author_decision false <<<"needs-triage"
check "later sweep accepts a normalized outside-authored issue" 0 "KEEP" queue_decision <<<"ready"

# Invariant 5: completed epics get one nudge; incomplete/unparseable do not.
epic_refs="$(epic_references <<< $'## Definition of done\n- [ ] outside #8\n\n## Task list\n- [ ] #3 first\n- [x] #2 done\nplain #9')"
check "epic parser reads task-list refs only" 0 $'2\n3' printf '%s\n' "$epic_refs"
body=$'## Task list\n- [x] #2 done\n- [x] #3 done\n\n## Definition of done\n- [ ] open issue #99 must not suppress the nudge'
check "epic parser stops before later checkbox sections" 0 "" test \
  "$(epic_references <<<"$body")" = $'2\n3'
check "completed epic is nudged" 0 "NUDGE" epic_decision "$epic_refs" $'CLOSED\nCLOSED'
check "open epic child suppresses nudge" 0 "KEEP" epic_decision "$epic_refs" $'CLOSED\nOPEN'
check "epic without parseable children is stable" 0 "KEEP" epic_decision "" ""

summary
