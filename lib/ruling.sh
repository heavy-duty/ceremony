#!/usr/bin/env bash
# lib/ruling.sh — the `needs-ruling` sweep invariants (issue #52, epic #50).
#
# Both reconcilers source this file: the bare-flag check and the 7-day nudge
# are ONE implementation serving both surfaces — two copies of a 7-day rule
# is how the family got here in the first place (#50). Pure decisions sit
# above the divider (facts in, verdict out); the one impure orchestrator
# below talks to gh and posts through the sourcing script's run()/log().
#
# Standing rules this file lives under:
#   - The machine never sets or clears `needs-ruling` (#50 D9). Nothing here
#     mutates a label; the only writes are comments. Pinned by a sweep-probe
#     test and a grep-level check over the mutation calls.
#   - The machine never judges prose (#50 D4). "Did the escalation contract
#     accompany the flag" is decided by a mechanical proxy: the actor who
#     applied the label has a comment timestamped no earlier than 15 minutes
#     before the `labeled` event. The back-window exists because the natural
#     ordering is post-the-escalation-then-set-the-label, seconds apart; a
#     strictly-after rule would flag every correctly-formed escalation.
#   - The failure direction is always *flag*, never *act*: a bare flag is
#     commented on, never removed (removing would delete somebody's
#     escalation on the strength of a timestamp heuristic), and an
#     unreadable timeline does nothing at all — an unreadable fact must
#     never invent a verdict (the reconciler's standing rule).

# One constant, both surfaces — the whole reason this file exists. 7 days
# (#50 D10): long enough that an active back-and-forth is never nudged,
# short enough that a forgotten ruling surfaces within the week.
RULING_NUDGE_AFTER=$((7 * 24 * 3600))
# The escalation back-window: a comment this many seconds before the
# `labeled` event still accompanies it.
RULING_BARE_WINDOW=$((15 * 60))
# The idempotency marker for the bare-flag comment. The nudge deliberately
# has NO marker — see ruling_nudge_decision.
RULING_BARE_MARKER='<!-- ceremony:needs-ruling-bare -->'

# ---------------------------------------------------------------------------
# Pure decisions. Facts in (args/stdin), verdict out. No gh, no clock.
# ---------------------------------------------------------------------------

ruling_stale_exempt() { # labels on stdin → EXEMPT | SWEEP
  # Waiting on a human is legitimately quiet (#50 D10): under a pending
  # ruling the staleness clock does not run, the same treatment `blocked`
  # gets. The PR-side skip is #51's and lives in labels-reconcile.sh; this
  # verdict drives the ISSUE side (the claim-reclaim clock), so the rule has
  # one spelling even though the two surfaces consult it in different places.
  if grep -qxF needs-ruling; then echo EXEMPT; else echo SWEEP; fi
}

ruling_accompanies() { # $1 comment epoch, $2 labeled epoch → 0 iff in-window
  # One spelling of the window rule, shared by the bare verdict and the
  # escalation-comment lookup the nudge links — two comparisons drifting
  # apart would let the nudge link a comment the bare check rejected.
  [ "$1" -ge "$(($2 - RULING_BARE_WINDOW))" ]
}

ruling_bare_decision() { # $1 setter, $2 labeled epoch; "login epoch" lines on stdin
  # → ACCOMPANIED | BARE. Only the flag-setter's own comments count: the
  # escalation contract (question, options, recommendation — #50 D4) is the
  # flag-setter's to post, and somebody else's chatter must not satisfy it.
  local setter="$1" labeled="$2" login epoch
  while read -r login epoch; do
    [ -n "$login" ] || continue
    [ "$login" = "$setter" ] || continue
    if ruling_accompanies "$epoch" "$labeled"; then
      echo ACCOMPANIED
      return 0
    fi
  done
  echo BARE
}

ruling_bare_comment_needed() { # $1 labeled epoch, $2 newest marked-comment epoch ("" = none)
  # → POST | SKIP. Scoped to the CURRENT labeled event: a marked comment
  # older than the event belongs to an earlier flag episode, so a genuine
  # re-flag is re-checked while a 15-minute cron never repeats itself.
  local labeled="$1" marked="${2:-}"
  if [ -n "$marked" ] && [ "$marked" -gt "$labeled" ]; then
    echo SKIP
  else
    echo POST
  fi
}

ruling_nudge_decision() { # $1 now, $2 last real-activity epoch → NUDGE | KEEP
  # Real activity only — comments, reviews, commits, never label churn, or
  # the sweep would reset its own clock. The nudge needs NO marker: the
  # nudge comment is itself activity, so posting it resets this window and
  # the rule self-rate-limits to at most one nudge per 7 quiet days. That is
  # deliberate — a later refactor that "fixes" it by adding a marker breaks
  # exactly the property that makes it safe on a 15-minute cron.
  if [ "$(($1 - $2))" -gt "$RULING_NUDGE_AFTER" ]; then echo NUDGE; else echo KEEP; fi
}

ruling_newest_flag() { # "login<TAB>iso8601" lines on stdin → the newest line
  # A re-flag after a removal is judged on its own escalation, never on the
  # last one's — so every fact anchors to the MOST RECENT labeled event.
  # ISO-8601 UTC sorts lexically, so no date parsing is needed here.
  sort -t $'\t' -k2 | tail -n1
}

ruling_escalation_url() { # $1 setter, $2 labeled epoch; "login epoch url" lines on stdin
  # → the url of the EARLIEST in-window comment by the setter, or nothing.
  # Earliest, because the natural shape is escalation-then-flag: the first
  # qualifying comment is the escalation itself, later ones are follow-ups.
  local setter="$1" labeled="$2" login epoch url best_epoch="" best_url=""
  while read -r login epoch url; do
    [ -n "$login" ] || continue
    [ "$login" = "$setter" ] || continue
    ruling_accompanies "$epoch" "$labeled" || continue
    if [ -z "$best_epoch" ] || [ "$epoch" -lt "$best_epoch" ]; then
      best_epoch="$epoch"
      best_url="$url"
    fi
  done
  [ -z "$best_url" ] || printf '%s\n' "$best_url"
}

# ---------------------------------------------------------------------------
# The impure orchestrator: fetch the facts, call the decisions, post through
# the caller's run(). Called by both reconcilers for every open item that
# carries the flag. Needs REPO; uses the caller's run() and log().
# ---------------------------------------------------------------------------

reconcile_ruling() { # $1 item number, $2 last real-activity epoch, $3 now
  local n="$1" last_activity="$2" now="$3"
  : "${REPO:?reconcile_ruling: REPO is required}"

  # The newest `labeled` event for the flag: actor + timestamp. A failed read
  # skips BOTH checks — the nudge's specified content links the escalation
  # comment, which only these facts identify, and half-verdicts on half-read
  # facts is the exact shape the reconciler's standing rule forbids.
  local flags newest setter labeled_at labeled_epoch
  if ! flags="$(gh api --paginate "repos/$REPO/issues/$n/timeline" \
    --jq '.[] | select(.event == "labeled" and .label.name == "needs-ruling")
          | [.actor.login, .created_at] | @tsv' 2>/dev/null)"; then
    log "#$n: ruling timeline unreadable — no verdict invented this pass"
    return 0
  fi
  if [ -z "$flags" ]; then
    # The label is on the item but no labeled event is visible (a timeline
    # hiccup, or an import). Same treatment as unreadable: do nothing.
    log "#$n: ruling flag has no visible labeled event — no verdict invented this pass"
    return 0
  fi
  newest="$(ruling_newest_flag <<<"$flags")"
  setter="${newest%%$'\t'*}"
  labeled_at="${newest##*$'\t'}"
  labeled_epoch="$(date -d "$labeled_at" +%s)"

  local comments
  if ! comments="$(gh api --paginate "repos/$REPO/issues/$n/comments" \
    --jq '.[] | [.user.login, .created_at, .html_url,
          (if ((.body // "") | contains("<!-- ceremony:needs-ruling-bare -->"))
           then "marked" else "plain" end)] | @tsv' 2>/dev/null)"; then
    log "#$n: ruling comments unreadable — no verdict invented this pass"
    return 0
  fi

  # One pass over the comments builds every fact the decisions consume:
  # who commented when (for the bare verdict), the newest marked comment
  # (for idempotency), and the "login epoch url" rows the link lookup reads.
  local login at url kind epoch authored="" rows="" marked=""
  while IFS=$'\t' read -r login at url kind; do
    [ -n "$login" ] || continue
    epoch="$(date -d "$at" +%s)"
    authored="$authored$login $epoch"$'\n'
    rows="$rows$login $epoch $url"$'\n'
    if [ "$kind" = marked ]; then
      if [ -z "$marked" ] || [ "$epoch" -gt "$marked" ]; then marked="$epoch"; fi
    fi
  done <<<"$comments"

  # ---- the bare-flag check (#50 D4, mechanical proxy) ----
  if [ "$(ruling_bare_decision "$setter" "$labeled_epoch" <<<"$authored")" = BARE ] \
    && [ "$(ruling_bare_comment_needed "$labeled_epoch" "$marked")" = POST ]; then
    run gh issue comment "$n" -R "$REPO" --body "$RULING_BARE_MARKER
The ruling flag on this item was set by @$setter with no accompanying
escalation comment. Setting it requires the escalation contract — the
**question**, the **options**, and a **recommendation** — posted by the
flag-setter no more than 15 minutes before applying the label, or any time
after ([LABELS.md](https://github.com/heavy-duty/ceremony/blob/main/LABELS.md)
carries the flag-setter's obligations; heavy-duty/ceremony#50 D4). The label stays — this machine never removes an
escalation on the strength of a timestamp heuristic — but the contract is
still owed." >/dev/null
    log "#$n: ruling flag is bare — commented (the label is never removed)"
  fi

  # ---- the 7-day nudge (#50 D10) ----
  if [ "$(ruling_nudge_decision "$now" "$last_activity")" = NUDGE ]; then
    # The decider is the repo's human reviewer — the same knob the PR
    # reconciler trusts for the merge gate, defaulted the same way. The
    # flag-setter is named but deliberately not tagged: address the decider,
    # never the whole thread's cast (#50 D10).
    local decider="${HUMAN_REVIEWER:-danmt}" days esc_url esc_line
    days=$(((now - last_activity) / 86400))
    esc_url="$(ruling_escalation_url "$setter" "$labeled_epoch" <<<"$rows")"
    if [ -n "$esc_url" ]; then
      esc_line="The escalation is here: $esc_url"
    else
      esc_line="No escalation comment accompanies the flag — the contract (question, options, recommendation) is still owed by the flag-setter."
    fi
    run gh issue comment "$n" -R "$REPO" --body "@$decider — a ruling on this item has been pending with no activity for ${days} days. $esc_line

Per heavy-duty/ceremony#50 D6/D7 the flag-setter ($setter) owns closing this out: judge when agreement is reached, record the ruling as a decision in one comment, remove the label, and return the item to its flow in that same comment.

*This nudge is comment-only and carries no idempotency marker on purpose: the comment itself is activity, so posting it resets the 7-day window and the rule self-rate-limits. Do not add a marker.*" >/dev/null
    log "#$n: ruling nudge (${days}d quiet — the decider owes an answer)"
  fi
}
