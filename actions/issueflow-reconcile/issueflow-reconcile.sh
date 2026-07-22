#!/usr/bin/env bash
# shellcheck disable=SC2016 # backticks in comment bodies are Markdown literals
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  set -euo pipefail
else
  set -u
fi

# The issue-flow half of the labels state machine. Decisions are pure strings;
# API calls live below the divider so fixture tests can exercise every branch.

STALE_AFTER=$((48 * 3600))
QUEUE_LABELS=(ready claimed blocked)
TRIAGE_ACTORS=()

log() { printf 'issueflow: %s\n' "$*"; }
run() { if [ -n "${DRY_RUN:-}" ]; then log "DRY_RUN: $*"; else "$@"; fi; }

load_issueflow_config() { # $1 = labels.conf
  local conf="$1" line seen=false
  [ -f "$conf" ] || { echo "issueflow: missing config: $conf" >&2; return 1; }
  TRIAGE_ACTORS=()
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      triage-actors=*)
        [ "$seen" = false ] || {
          echo "issueflow: duplicate triage-actors line in $conf" >&2
          return 1
        }
        seen=true
        read -r -a TRIAGE_ACTORS <<<"${line#triage-actors=}"
        [ "${#TRIAGE_ACTORS[@]}" -gt 0 ] || {
          echo "issueflow: triage-actors must name at least one actor in $conf" >&2
          return 1
        }
        ;;
    esac
  done <"$conf"
  [ "$seen" = true ] || {
    echo "issueflow: missing triage-actors= line in $conf" >&2
    return 1
  }
}

is_triage_actor() {
  local actor
  for actor in "${TRIAGE_ACTORS[@]}"; do
    [ "$actor" = "$1" ] && return 0
  done
  return 1
}

has_issue_label() { grep -qxF "$1" <<<"$ISSUE_LABELS"; }

queue_decision() { # labels on stdin -> KEEP | ADD_NEEDS_TRIAGE | FLAG_CONFLICT
  local labels count=0 label categories=0
  labels="$(cat)"
  grep -qxF needs-triage <<<"$labels" && categories=$((categories + 1))
  grep -qxF epic <<<"$labels" && categories=$((categories + 1))
  for label in "${QUEUE_LABELS[@]}"; do
    if grep -qxF "$label" <<<"$labels"; then count=$((count + 1)); fi
  done
  [ "$count" -gt 0 ] && categories=$((categories + 1))
  if [ "$categories" -eq 0 ]; then echo ADD_NEEDS_TRIAGE
  elif [ "$categories" -gt 1 ] || [ "$count" -gt 1 ]; then echo FLAG_CONFLICT
  else echo KEEP
  fi
}

author_decision() { # $1 = true when author is triage; labels on stdin
  local triage="$1" labels
  labels="$(cat)"
  if [ "$triage" = false ] && ! grep -qxF needs-triage <<<"$labels"; then
    echo ADD_NEEDS_TRIAGE
  else echo KEEP
  fi
}

claim_decision() { # $1 assignee count, $2 linked open PR, $3 age seconds
  local assignees="$1" open_pr="$2" age="$3"
  if [ "$assignees" -eq 0 ]; then echo FLAG_UNASSIGNED
  elif [ "$open_pr" = true ] || [ "$age" -le "$STALE_AFTER" ]; then echo KEEP
  else echo RECLAIM
  fi
}

blocked_references() { # body on stdin -> issue numbers, one per line
  sed -nE 's/^[[:space:]]*Blocked by[[:space:]]+//Ip' \
    | { grep -Eo '#[0-9]+' || true; } | tr -d '#' | sort -nu
}

blocked_decision() { # $1 refs, $2 OPEN/CLOSED states
  local refs="$1" states="$2"
  if [ -z "$refs" ]; then echo FLAG_UNPARSEABLE
  elif grep -qxF OPEN <<<"$states"; then echo KEEP
  elif grep -qxF UNKNOWN <<<"$states"; then echo FLAG_UNPARSEABLE
  else echo READY
  fi
}

epic_references() { # markdown task-list issue references from body on stdin
  sed -nE '/^[[:space:]]*[-*][[:space:]]+\[[ xX]\]/ { s/.*#([0-9]+).*/\1/p; }' \
    | sort -nu
}

epic_decision() { # $1 refs, $2 states
  local refs="$1" states="$2"
  if [ -n "$refs" ] && ! grep -Eq '^(OPEN|UNKNOWN)$' <<<"$states"; then echo NUDGE
  else echo KEEP
  fi
}

# API edge. Marker comments make warnings and nudges idempotent across sweeps.
ensure_comment() { # $1 issue, $2 marker, $3 message
  local n="$1" marker="$2" message="$3"
  if gh api --paginate "repos/$REPO/issues/$n/comments" --jq '.[].body' \
      | grep -qF "<!-- issueflow:$marker -->"; then return; fi
  run gh issue comment "$n" -R "$REPO" --body "<!-- issueflow:$marker -->
$message" >/dev/null
}

reference_states() {
  local ref state
  while IFS= read -r ref; do
    [ -n "$ref" ] || continue
    state="$(gh api "repos/$REPO/issues/$ref" --jq '.state' 2>/dev/null || echo UNKNOWN)"
    case "$state" in open) echo OPEN ;; closed) echo CLOSED ;; *) echo UNKNOWN ;; esac
  done
}

last_issue_activity() {
  local n="$1" created="$2" latest
  latest="$({ printf '%s\n' "$created"; gh api --paginate "repos/$REPO/issues/$n/comments" --jq '.[].created_at'; } \
    | sort | tail -n1)"
  date -d "$latest" +%s
}

reconcile_issue() {
  local n="$1" author triage=false decision refs states age assignees open_pr=false remove="" label owners
  author="$(jq -r '.user.login' <<<"$ISSUE_JSON")"
  is_triage_actor "$author" && triage=true
  decision="$(author_decision "$triage" <<<"$ISSUE_LABELS")"
  if [ "$decision" = ADD_NEEDS_TRIAGE ]; then
    for label in epic "${QUEUE_LABELS[@]}"; do
      has_issue_label "$label" && remove="$remove,$label"
    done
    remove="${remove#,}"
    if [ -n "$remove" ]; then
      run gh issue edit "$n" -R "$REPO" --add-label needs-triage --remove-label "$remove" >/dev/null
    else
      run gh issue edit "$n" -R "$REPO" --add-label needs-triage >/dev/null
    fi
    log "#$n: needs-triage (opened by $author)"
    ISSUE_LABELS=needs-triage
  fi

  decision="$(queue_decision <<<"$ISSUE_LABELS")"
  case "$decision" in
    ADD_NEEDS_TRIAGE)
      run gh issue edit "$n" -R "$REPO" --add-label needs-triage >/dev/null
      log "#$n: needs-triage (no queue state)" ;;
    FLAG_CONFLICT)
      ensure_comment "$n" queue-conflict \
        'The issue-flow sweep found conflicting queue labels. It cannot infer intent safely; triage must leave exactly one of `needs-triage`, `epic`, `ready`, `claimed`, or `blocked`.'
      log "#$n: conflicting queue labels; flagged"
      return ;;
  esac

  if has_issue_label claimed; then
    assignees="$(jq '.assignees | length' <<<"$ISSUE_JSON")"
    grep -qxF "$n" <<<"${OPEN_PR_ISSUES:-}" && open_pr=true
    age=$((NOW - $(last_issue_activity "$n" "$(jq -r '.created_at' <<<"$ISSUE_JSON")")))
    decision="$(claim_decision "$assignees" "$open_pr" "$age")"
    case "$decision" in
      FLAG_UNASSIGNED)
        ensure_comment "$n" claimed-unassigned \
          'This issue is `claimed` but has no assignee. The sweep cannot infer an owner; triage must repair the claim.' ;;
      RECLAIM)
        ensure_comment "$n" claim-reclaimed \
          'This claim has no linked open PR and no activity for 48 hours. The sweep is reclaiming it for the ready queue.'
        owners="$(jq -r '[.assignees[].login] | join(",")' <<<"$ISSUE_JSON")"
        run gh issue edit "$n" -R "$REPO" --remove-assignee "$owners" \
          --remove-label claimed --add-label ready >/dev/null
        log "#$n: stale claim reclaimed -> ready" ;;
    esac
  elif has_issue_label blocked; then
    refs="$(blocked_references <<<"$(jq -r '.body // ""' <<<"$ISSUE_JSON")")"
    states="$(reference_states <<<"$refs")"
    decision="$(blocked_decision "$refs" "$states")"
    case "$decision" in
      FLAG_UNPARSEABLE)
        ensure_comment "$n" blocked-unparseable \
          'This issue is `blocked`, but its body has no parseable `Blocked by #N` declaration. The sweep will not guess the dependency.' ;;
      READY)
        ensure_comment "$n" blockers-cleared \
          'Every issue named by `Blocked by` is closed. The sweep is moving this issue to `ready`.'
        run gh issue edit "$n" -R "$REPO" --remove-label blocked --add-label ready >/dev/null
        log "#$n: blockers closed -> ready" ;;
    esac
  elif has_issue_label epic; then
    refs="$(epic_references <<<"$(jq -r '.body // ""' <<<"$ISSUE_JSON")")"
    states="$(reference_states <<<"$refs")"
    if [ "$(epic_decision "$refs" "$states")" = NUDGE ]; then
      ensure_comment "$n" epic-complete \
        "Every issue referenced by this epic's task list is closed. Please close the epic or extend its task list."
      log "#$n: completed epic nudged"
    fi
  fi
}

main() {
  REPO="${REPO:?set REPO to owner/name}"
  LABELS_CONF="${LABELS_CONF:-.github/labels.conf}"
  load_issueflow_config "$LABELS_CONF"
  NOW="$(date +%s)"
  OPEN_PR_ISSUES="$(gh pr list -R "$REPO" --state open --limit 100 \
    --json closingIssuesReferences --jq '.[].closingIssuesReferences[].number' | sort -nu)"

  local n
  for n in $(gh issue list -R "$REPO" --state open --limit 100 --json number --jq '.[].number'); do
    (
      ISSUE_JSON="$(gh api "repos/$REPO/issues/$n")"
      jq -e 'has("pull_request") | not' <<<"$ISSUE_JSON" >/dev/null || exit 0
      ISSUE_LABELS="$(jq -r '.labels[].name' <<<"$ISSUE_JSON")"
      reconcile_issue "$n"
    ) || log "#$n: reconcile failed — continuing with the remaining issues"
  done
  log "reconciled."
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then main "$@"; fi
