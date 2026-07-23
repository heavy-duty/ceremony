#!/usr/bin/env bash
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=test/harness.sh
source "$ROOT/test/harness.sh"
# shellcheck source=lib/ruling.sh
source "$ROOT/lib/ruling.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------------------
# Pure decisions. Epochs are arbitrary fixed numbers — no wall clock anywhere.
# ---------------------------------------------------------------------------

check "needs-ruling is stale-exempt" 0 "EXEMPT" ruling_stale_exempt <<< $'claimed\nneeds-ruling'
check "a flag-free issue sweeps normally" 0 "SWEEP" ruling_stale_exempt <<< $'claimed'

L=100000 # the labeled event, in every window case below

check "escalation 14 minutes before the flag accompanies it" 0 "ACCOMPANIED" \
  ruling_bare_decision setter "$L" <<<"setter $((L - 840))"
check "escalation exactly 15 minutes before still accompanies (no earlier than)" 0 "ACCOMPANIED" \
  ruling_bare_decision setter "$L" <<<"setter $((L - 900))"
check "escalation after the flag accompanies it" 0 "ACCOMPANIED" \
  ruling_bare_decision setter "$L" <<<"setter $((L + 60))"
check "escalation 16 minutes before is bare" 0 "BARE" \
  ruling_bare_decision setter "$L" <<<"setter $((L - 960))"
check "somebody else's comment does not satisfy the contract" 0 "BARE" \
  ruling_bare_decision setter "$L" <<<"bystander $((L - 60))"
check "no comment at all is bare" 0 "BARE" \
  ruling_bare_decision setter "$L" </dev/null

# Re-flag: every fact anchors to the NEWEST labeled event, so an escalation
# that accompanied the first flag does not satisfy the second.
L2=$((L + 7200))
newest="$(ruling_newest_flag <<< "$(printf 'setter\t2020-01-01T00:00:00Z\nsetter\t2020-01-01T02:00:00Z\n')")"
check "the newest labeled event wins" 0 "" test "$newest" = "$(printf 'setter\t2020-01-01T02:00:00Z')"
check "first-flag escalation does not satisfy a re-flag" 0 "BARE" \
  ruling_bare_decision setter "$L2" <<<"setter $((L - 60))"

check "no marked comment yet posts" 0 "POST" ruling_bare_comment_needed "$L" ""
check "a marked comment newer than the event skips" 0 "SKIP" ruling_bare_comment_needed "$L" $((L + 300))
check "a marked comment from an earlier flag episode re-posts" 0 "POST" ruling_bare_comment_needed "$L2" $((L + 300))

NOW=2000000000
check "8 days of silence nudges" 0 "NUDGE" ruling_nudge_decision "$NOW" $((NOW - 8 * 86400))
check "6 days of silence holds" 0 "KEEP" ruling_nudge_decision "$NOW" $((NOW - 6 * 86400))
check "exactly 7 days holds — strictly past the horizon, like the stale sweep" 0 "KEEP" \
  ruling_nudge_decision "$NOW" $((NOW - 7 * 86400))
check "fresh activity holds" 0 "KEEP" ruling_nudge_decision "$NOW" $((NOW - 60))

rows="$(printf 'setter %s https://x/first\nsetter %s https://x/late\nbystander %s https://x/other\nsetter %s https://x/early-out\n' \
  "$((L - 300))" "$((L + 600))" "$((L - 60))" "$((L - 5000))")"
check "the nudge links the earliest in-window escalation by the setter" 0 "https://x/first" \
  ruling_escalation_url setter "$L" <<<"$rows"
check "no qualifying escalation yields no link" 0 "" \
  ruling_escalation_url setter "$L" <<<"bystander $((L - 60)) https://x/other"

# ---------------------------------------------------------------------------
# The orchestrator, against a recording gh stub. The stub serves fixture JSON
# per endpoint (missing file = unreadable read), applies the caller's --jq
# with real jq, appends posted comments back into the fixture (so a second
# sweep sees the first sweep's writes, exactly like the live board), and
# records every `gh issue edit` — which must never happen from this code.
# ---------------------------------------------------------------------------

REPO=owner/repo
log() { printf 'test-sweep: %s\n' "$*"; }
run() { "$@"; }

iso() { date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ; }

gh() {
  if [ "$1" = api ]; then
    shift
    local jqexpr="" endpoint="" file
    while [ $# -gt 0 ]; do
      case "$1" in
        --jq) jqexpr="$2"; shift ;;
        -*) ;;
        *) [ -n "$endpoint" ] || endpoint="$1" ;;
      esac
      shift
    done
    file="$TMP/$(printf '%s' "$endpoint" | tr '/' '_').json"
    [ -f "$file" ] || return 1
    if [ -n "$jqexpr" ]; then jq -r "$jqexpr" "$file"; else cat "$file"; fi
  elif [ "$1" = issue ] && [ "$2" = comment ]; then
    local n="$3" body="" file
    shift 3
    while [ $# -gt 0 ]; do
      case "$1" in --body) body="$2"; shift ;; esac
      shift
    done
    printf '%s\n----\n' "$body" >>"$TMP/posted-$n"
    file="$TMP/repos_${REPO%%/*}_${REPO#*/}_issues_${n}_comments.json"
    [ -f "$file" ] || printf '[]\n' >"$file"
    jq --arg b "$body" --arg at "$(iso "$NOW")" \
      '. + [{"user":{"login":"sweep-bot"},"created_at":$at,"html_url":"https://x/posted","body":$b}]' \
      "$file" >"$file.tmp" && mv "$file.tmp" "$file"
  elif [ "$1" = issue ] && [ "$2" = edit ]; then
    printf '%s\n' "$*" >>"$TMP/edits"
  fi
}

posts() { [ -f "$TMP/posted-$1" ] && grep -c '^----$' "$TMP/posted-$1" || echo 0; }
timeline_file() { printf '%s/repos_owner_repo_issues_%s_timeline.json' "$TMP" "$1"; }
comments_file() { printf '%s/repos_owner_repo_issues_%s_comments.json' "$TMP" "$1"; }

# -- bare flag, swept twice: exactly one comment -----------------------------
T=$((NOW - 3600))
jq -n --arg at "$(iso "$T")" \
  '[{"event":"labeled","label":{"name":"needs-ruling"},"actor":{"login":"setter"},"created_at":$at}]' \
  >"$(timeline_file 9)"
printf '[]\n' >"$(comments_file 9)"
check "a bare flag is commented on" 0 "ruling flag is bare" reconcile_ruling 9 "$T" "$NOW"
check "...and the sweep never posted twice" 0 "" reconcile_ruling 9 "$T" "$NOW"
check "one bare comment across two sweeps" 0 "1" posts 9
check "the bare comment carries its marker" 0 "" \
  grep -qF '<!-- ceremony:needs-ruling-bare -->' "$TMP/posted-9"
check "the bare comment names the missing contract" 0 "" \
  grep -q 'question' "$TMP/posted-9"

# -- accompanied flag: silence ----------------------------------------------
jq -n --arg at "$(iso "$T")" \
  '[{"event":"labeled","label":{"name":"needs-ruling"},"actor":{"login":"setter"},"created_at":$at}]' \
  >"$(timeline_file 10)"
jq -n --arg at "$(iso "$((T - 840))")" \
  '[{"user":{"login":"setter"},"created_at":$at,"html_url":"https://x/esc","body":"question, options, recommendation"}]' \
  >"$(comments_file 10)"
reconcile_ruling 10 "$T" "$NOW" >/dev/null
check "an accompanied flag posts nothing" 0 "0" posts 10

# -- re-flag: judged on its own escalation, marker scoped per event ----------
T1=$((NOW - 86400)) T2=$((NOW - 7200))
jq -n --arg t1 "$(iso "$T1")" --arg t2 "$(iso "$T2")" \
  '[{"event":"labeled","label":{"name":"needs-ruling"},"actor":{"login":"setter"},"created_at":$t1},
    {"event":"unlabeled","label":{"name":"needs-ruling"},"actor":{"login":"setter"},"created_at":$t2},
    {"event":"labeled","label":{"name":"needs-ruling"},"actor":{"login":"setter"},"created_at":$t2}]' \
  >"$(timeline_file 11)"
jq -n --arg esc "$(iso "$((T1 - 60))")" --arg marked "$(iso "$((T1 + 300))")" \
  '[{"user":{"login":"setter"},"created_at":$esc,"html_url":"https://x/esc1","body":"the first escalation"},
    {"user":{"login":"sweep-bot"},"created_at":$marked,"html_url":"https://x/bare1","body":"<!-- ceremony:needs-ruling-bare -->\nolder episode"}]' \
  >"$(comments_file 11)"
reconcile_ruling 11 "$T2" "$NOW" >/dev/null
check "a re-flag is re-checked against its own escalation" 0 "1" posts 11

# -- nudge: fires past 7 quiet days, links the escalation, resets itself -----
T0=$((NOW - 8 * 86400))
jq -n --arg at "$(iso "$T0")" \
  '[{"event":"labeled","label":{"name":"needs-ruling"},"actor":{"login":"setter"},"created_at":$at}]' \
  >"$(timeline_file 12)"
jq -n --arg at "$(iso "$((T0 - 60))")" \
  '[{"user":{"login":"setter"},"created_at":$at,"html_url":"https://x/esc12","body":"question, options, recommendation"}]' \
  >"$(comments_file 12)"
check "8 quiet days nudge" 0 "ruling nudge" reconcile_ruling 12 "$T0" "$NOW"
check "one nudge posted" 0 "1" posts 12
check "the nudge links the escalation comment" 0 "" grep -qF 'https://x/esc12' "$TMP/posted-12"
check "the nudge addresses the decider" 0 "" grep -qF '@danmt' "$TMP/posted-12"
check "the nudge does not tag the flag-setter" 1 "" grep -qF '@setter' "$TMP/posted-12"
check "the nudge carries no marker — the comment itself resets the window" 1 "" \
  grep -qF "$RULING_BARE_MARKER" "$TMP/posted-12"
# The reset, through the surfaces' own activity computation: the nudge the
# stub appended is the newest comment, so the recomputed last-activity is NOW.
newest_at="$(jq -r 'map(.created_at) | max' "$(comments_file 12)")"
check "the posted nudge is now the newest activity" 0 "" \
  test "$(date -d "$newest_at" +%s)" = "$NOW"
reconcile_ruling 12 "$(date -d "$newest_at" +%s)" "$NOW" >/dev/null
check "a sweep right after the nudge holds its silence" 0 "1" posts 12

# -- 6 quiet days: silence ---------------------------------------------------
jq -n --arg at "$(iso "$((NOW - 6 * 86400))")" \
  '[{"event":"labeled","label":{"name":"needs-ruling"},"actor":{"login":"setter"},"created_at":$at}]' \
  >"$(timeline_file 13)"
jq -n --arg at "$(iso "$((NOW - 6 * 86400))")" \
  '[{"user":{"login":"setter"},"created_at":$at,"html_url":"https://x/esc13","body":"question, options, recommendation"}]' \
  >"$(comments_file 13)"
reconcile_ruling 13 $((NOW - 6 * 86400)) "$NOW" >/dev/null
check "6 quiet days do not nudge" 0 "0" posts 13

# -- unreadable timeline: nothing happens ------------------------------------
check "an unreadable timeline invents no verdict" 0 "timeline unreadable" \
  reconcile_ruling 14 "$T" "$NOW"
check "...and posts nothing" 0 "0" posts 14

# -- across every scenario above: not one label write ------------------------
check "the ruling sweep never wrote a label" 1 "" test -f "$TMP/edits"

# Grep-level pin for #50 D9: no mutation call in the sweep code names the
# flag. The only writes reconcile_ruling makes are comments.
check "no add/remove-label mutation names the ruling flag" 1 "" \
  grep -rEn -- '(add|remove)-label[^"]*needs-ruling' "$ROOT/actions" "$ROOT/lib"

summary
