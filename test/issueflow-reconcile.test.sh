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
check "qualified short repository reference drops" 0 "" test \
  -z "$(blocked_references <<<"Blocked by rig#112.")"
check "qualified owner/repository reference drops" 0 "" test \
  -z "$(blocked_references <<<"Blocked by heavy-duty/box#9.")"
check "parenthesized local reference survives" 0 "13" blocked_references <<<"Blocked by (#13)."
check "slash-adjacent local references survive" 0 $'14\n15' \
  blocked_references <<<"Blocked by #14/#15."
check "comma-adjacent local references survive" 0 $'11\n12' \
  blocked_references <<<"Blocked by #11, #12."
check "open blocker keeps issue blocked" 0 "KEEP" blocked_decision "$refs" $'CLOSED\nOPEN'
check "all closed blockers release issue" 0 "READY" blocked_decision "$refs" $'CLOSED\nCLOSED'
check "missing blocked declaration is flagged" 0 "FLAG_UNPARSEABLE" blocked_decision "" ""
check "unreadable blocker is flagged" 0 "FLAG_UNPARSEABLE" blocked_decision "12" "UNKNOWN"
check "cross-repo-only blocker is flagged distinctly" 0 "FLAG_CROSS_REPO" \
  blocked_decision "" "" "rig#112"
check "cross-repo blocker prevents false promotion when locals close" 0 "FLAG_CROSS_REPO" \
  blocked_decision "9" "CLOSED" "rig#9"
# shellcheck disable=SC2016 # expansions belong to the generated fake gh
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'if [ "$1" = api ]; then [ ! -f "$GH_COMMENTS" ] || cat "$GH_COMMENTS"; exit; fi' \
  'if [ "$1 $2" = "issue comment" ]; then' \
  '  while [ "$#" -gt 0 ]; do' \
  '    if [ "$1" = --body ]; then shift; printf "%s\n" "$1" >>"$GH_COMMENTS"; exit; fi' \
  '    shift' \
  '  done' \
  'fi' >"$TMP/gh"
chmod +x "$TMP/gh"
: >"$TMP/comments"
# shellcheck disable=SC2016 # expansions belong to the isolated bash -c process
check "cross-repo warning is idempotent across two sweeps" 0 "" \
  env PATH="$TMP:$PATH" GH_COMMENTS="$TMP/comments" bash -c \
  'source "$1"; REPO=heavy-duty/ceremony
  ensure_comment 99 blocked-cross-repo "cross-repo warning"
  ensure_comment 99 blocked-cross-repo "cross-repo warning"
  test "$(grep -cF "<!-- issueflow:blocked-cross-repo -->" "$GH_COMMENTS")" -eq 1' \
  _ "$ROOT/actions/issueflow-reconcile/issueflow-reconcile.sh"

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
# shellcheck disable=SC2016 # backticks and ${{ }}-shaped prose are fixture literals
body=$'## Task list\n\n- [x] #2 Scaffold: layout, test harness, shellcheck + actionlint CI\n- [x] #3 `lib/version.sh` — one version abstraction, two backends\n- [x] #4 `lib/changelog.sh` — the one canonical section extractor\n- [x] #5 `actions/changelog-armed` — the version-keyed arming guard\n- [x] #6 `actions/changelog-monotonic` — shipped release headings are append-only\n- [x] #7 `actions/drill-recorded` — a release carries its evidence\n- [x] #8 `lib/decide.sh` — the merge door'\''s decision, pure\n- [x] #9 The reusable release workflow — both doors, one implementation\n- [x] #10 Labels machinery: reusable workflow + core/scope split\n- [x] #11 Dogfood: ceremony releases itself (0.1.0) — **shipped: tag `0.1.0`, release, `drills/0.1.0.md`; main re-armed at `0.1.1-dev`**\n- [x] #12 `docs/CONSUMERS.md` + README doctrine\n- [ ] #13 Convert rig (pilot) — **PR [rig#112](https://github.com/heavy-duty/rig/pull/112) is approved by the whole panel on head `3c72c1b` and sits at `state:needs-human` since 2026-07-23 10:47Z; the merge is the human'\''s. #14/#15 unblock when it lands**\n- [ ] #14 Convert box\n- [ ] #15 Convert cast (artifact hook debut)\n- [ ] #16 Adopt in incubator (greenfield consumer)\n\nAdjacent, same repo, separable from the release chain: the **agent team flow** (discussion → triage → issue → build → review → human merge) landed as doctrine in PR #17 (CONTRIBUTING.md, LABELS.md, TRIAGE.md, BUILDER.md, REVIEWER.md); #10'\''s bootstrap carries its labels, #12'\''s guide carries its adoption checklist. Consumption is split by what has a runtime: **machinery by reference** (GitHub materializes pinned workflows/actions at run time), **doctrine as a machine-verified mirror** (`.ceremony/` in each consumer, byte-identical to the pin, CI-guarded — agents read rules from the checkout, never cross-repo):\n\n- [x] #18 Issue-flow reconciliation — the work-queue sweep — **shipped 2026-07-23** in #32 (`66f1c08`)\n- [ ] #61 issueflow-reconcile — cross-repo references must not be read as local issue numbers (found in triage hygiene against the live corpus after #18 shipped; it is why this epic cannot currently be nudged complete)\n- [x] #19 actions/docs-sync — the vendored-doctrine mirror + guard\n- [x] #24 Entry templates — the pipeline'\''s doors made mechanical (from discussion #23)\n- [ ] #50 `needs-ruling` — the pending-human-decision flag (its own epic; from discussion #30)\n- [ ] #56 Fleet scope and cross-repo discovery — the two guards, the runner hole, the roster question (its own epic; from discussion #55, filed at @danmt'\''s request). Children: #57 (BUILDER/REVIEWER/FLEET discovery guards), #58 (`actions/runner-isolated`). Added to this list by triage 2026-07-23 — it is agent-team-flow work like #50, so a scan of this epic must see it.'
check "real epic 1 task list drops rig PR and retains local references" 0 \
  $'2\n3\n4\n5\n6\n7\n8\n9\n10\n11\n12\n13\n14\n15\n16\n18\n19\n23\n24\n30\n32\n50\n55\n56\n57\n58\n61' \
  epic_references <<<"$body"
check "completed epic is nudged" 0 "NUDGE" epic_decision "$epic_refs" $'CLOSED\nCLOSED'
check "open epic child suppresses nudge" 0 "KEEP" epic_decision "$epic_refs" $'CLOSED\nOPEN'
check "epic without parseable children is stable" 0 "KEEP" epic_decision "" ""

summary
