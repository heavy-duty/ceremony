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

# Invariant 1: exactly one queue category.
check "one ready queue label is valid" 0 "KEEP" queue_decision <<<"ready"
check "zero queue labels is derivably needs-triage" 0 "ADD_NEEDS_TRIAGE" queue_decision <<<"enhancement"
check "multiple queue labels are ambiguous" 0 "FLAG_CONFLICT" queue_decision <<< $'ready\nblocked'
check "needs-triage plus queue is a conflict" 0 "FLAG_CONFLICT" queue_decision <<< $'needs-triage\nready'

# Invariant 2: claims have an owner and either a PR or recent activity.
check "claim with open PR stays claimed" 0 "KEEP" claim_decision 1 true 999999
check "recent claim without PR stays claimed" 0 "KEEP" claim_decision 1 false 60
check "unassigned claim is flagged" 0 "FLAG_UNASSIGNED" claim_decision 0 false 60
check "quiet claim without PR is reclaimed" 0 "RECLAIM" claim_decision 1 false $((STALE_AFTER + 1))
check "quiet unassigned claim is also reclaimed" 0 "RECLAIM" claim_decision 0 false $((STALE_AFTER + 1))

# Invariant 3: blocked declarations parse and release only when all close.
refs="$(blocked_references <<< $'Context #99\nBlocked by #12 and #7')"
check "blocked declaration extracts only declared refs" 0 $'7\n12' printf '%s\n' "$refs"
check "open blocker keeps issue blocked" 0 "KEEP" blocked_decision "$refs" $'CLOSED\nOPEN'
check "all closed blockers release issue" 0 "READY" blocked_decision "$refs" $'CLOSED\nCLOSED'
check "missing blocked declaration is flagged" 0 "FLAG_UNPARSEABLE" blocked_decision "" ""
check "unreadable blocker is flagged" 0 "FLAG_UNPARSEABLE" blocked_decision "12" "UNKNOWN"

# Invariant 4: only configured triage actors mint directly into the queue.
check "triage-authored ready issue is accepted" 0 "KEEP" author_decision true <<<"ready"
check "outside author receives needs-triage" 0 "ADD_NEEDS_TRIAGE" author_decision false <<<"ready"
check "outside author already marked needs-triage is stable" 0 "KEEP" author_decision false <<<"needs-triage"

# Invariant 5: completed epics get one nudge; incomplete/unparseable do not.
epic_refs="$(epic_references <<< $'- [ ] #3 first\n- [x] #2 done\nplain #8')"
check "epic parser reads task-list refs only" 0 $'2\n3' printf '%s\n' "$epic_refs"
check "completed epic is nudged" 0 "NUDGE" epic_decision "$epic_refs" $'CLOSED\nCLOSED'
check "open epic child suppresses nudge" 0 "KEEP" epic_decision "$epic_refs" $'CLOSED\nOPEN'
check "epic without parseable children is stable" 0 "KEEP" epic_decision "" ""

summary
