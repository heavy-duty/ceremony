#!/usr/bin/env bash
set -euo pipefail

# runner-isolated.sh [<workflows-dir>] — assert that no `pull_request`-
# triggered workflow in the tree names a self-hosted runner (#58; epic #56
# decision D5).
#
# The threat, stated once: a `pull_request` workflow runs code from the
# PR's branch. When that branch comes from a fork and the repo's fork-PR
# settings do not require approval, that code is UNREVIEWED. Point such a
# job at a self-hosted runner and unreviewed code executes on our own
# hardware, inside our own network. Nothing else in the fleet's setup
# gates that path — the write-token and secrets toggles (correctly off,
# #16's ruling) protect credentials, not the runner.
#
# Nothing was wrong the day this was written: incubator's deploy.yml is
# push-triggered and self-hosted (legal), its pr-checks.yml is
# PR-triggered and hosted, and the rule lived as a sentence in
# pr-checks.yml's header, kept true by whoever remembered it. This guard
# is that sentence moved into CI — the same move drill-recorded made
# after three releases shipped through a documented-but-unenforced gate
# (its header: "that is not a gate, it is luck with good manners").
#
# THE RULE IS FILE-LEVEL, DELIBERATELY. The precise rule — no JOB
# reachable from a pull_request trigger runs self-hosted — needs a YAML
# parser, and a second parser in bash is a new class of guard bug bought
# in exchange for permitting a file shape we do not want. So: a file
# FAILS when its trigger block names pull_request (which also matches
# pull_request_target — intended) AND it names a self-hosted runner
# anywhere, even in a different job. The false positive has a clean,
# safer fix — SPLIT THE WORKFLOW; incubator already keeps pr-checks.yml
# apart from deploy.yml, which is the shape this guard asks for. False
# NEGATIVES are what a security guard must not have, and file-level
# granularity has none for the modelled threat: it can only be stricter
# than the precise rule, never laxer.
#
# Self-hosted detection covers two shapes, because the same-line rule
# alone ("runs-on and self-hosted on one line") would pass the
# block-sequence form — a false negative, the one defect this guard is
# not allowed to have:
#
#     runs-on: [self-hosted, ci-runner]      # same line: caught
#     runs-on:                               # block sequence: the bare
#       - self-hosted                        #   key opens a window over
#       - ci-runner                          #   its `- …` list items
#
# KNOWN LIMITS, named in action.yml's description too so a consumer
# never reads silence as coverage:
#   - workflow_call is not treated as PR-reachable in v1: a pull_request
#     caller plus a self-hosted callee is a real path this guard does not
#     see. Following `uses:` across files is the YAML-parsing problem
#     again, and the family has no such caller today (ceremony's own
#     release-exercise.yml is ubuntu-latest).
#   - indirection is not resolved: a runner group (`runs-on: {group: …}`)
#     or a matrix/expression value can reach self-hosted hardware without
#     the string appearing on any line this guard reads.
#
# Comments are skipped on BOTH halves of the rule: a workflow that merely
# mentions self-hosted in prose is not the bug (incubator's pr-checks.yml
# header is exactly that prose), and a guard that cried wolf on comments
# would be turned off within a week. A missing workflows directory is a
# PASS, not an error — most repos in the family have one, but a guard
# that fails on absence is a guard nobody adopts.
#
# A file of its own (not inlined in action.yml) so
# test/runner-isolated.test.sh can drive it against constructed trees —
# the same discipline as the four guards beside it.

workflows_dir="${1:-${WORKFLOWS_DIR:-.github/workflows}}"

if [ ! -d "$workflows_dir" ]; then
  echo "runner-isolated: no workflows directory at '$workflows_dir' — nothing to scan"
  exit 0
fi

shopt -s nullglob
files=("$workflows_dir"/*.yml "$workflows_dir"/*.yaml)

if [ "${#files[@]}" -eq 0 ]; then
  echo "runner-isolated: 0 workflow files under '$workflows_dir' — nothing to scan"
  exit 0
fi

offenders=0
for file in "${files[@]}"; do
  pr_triggered=0
  in_on=0
  in_runs_on=0
  hits=()

  lineno=0
  while IFS= read -r line || [ -n "$line" ]; do
    lineno=$((lineno + 1))

    # A blank line ends nothing: it is not a top-level key, and a YAML
    # sequence may legally continue past one.
    case "$line" in
      *[![:space:]]*) ;;
      *) continue ;;
    esac

    stripped="${line#"${line%%[![:space:]]*}"}"

    # Comment lines are invisible to both halves of the rule.
    case "$stripped" in
      '#'*) continue ;;
    esac

    # A line starting a top-level key opens or closes the trigger block.
    # YAML 1.1 parses bare `on` as a boolean, so some repos quote the
    # key — a guard that missed '"on":' would silently pass the file it
    # most needs to read.
    case "$line" in
      [![:space:]]*)
        in_runs_on=0
        case "$line" in
          'on:'*| '"on":'* | "'on':"*) in_on=1 ;;
          *) in_on=0 ;;
        esac
        ;;
    esac

    # Half one: the trigger. Checked on the `on:` line itself (scalar and
    # inline-list shapes) and on every line of its block.
    if [ "$in_on" -eq 1 ]; then
      case "$line" in
        *pull_request*) pr_triggered=1 ;;
      esac
    fi

    # Half two: the runner. The window a bare `runs-on:` key opened over
    # its list items closes at the first line that is not a `- …` item.
    if [ "$in_runs_on" -eq 1 ]; then
      case "$stripped" in
        '-'*)
          case "$line" in
            *self-hosted*) hits+=("$lineno: $line") ;;
          esac
          ;;
        *) in_runs_on=0 ;;
      esac
    fi
    case "$line" in
      *runs-on*)
        case "$line" in
          *self-hosted*) hits+=("$lineno: $line") ;;
        esac
        case "$stripped" in
          'runs-on:' | 'runs-on:'[[:space:]]*)
            rest="${stripped#runs-on:}"
            rest="${rest#"${rest%%[![:space:]]*}"}"
            case "$rest" in
              '' | '#'*) in_runs_on=1 ;;
            esac
            ;;
        esac
        ;;
    esac
  done <"$file"

  if [ "$pr_triggered" -eq 1 ] && [ "${#hits[@]}" -gt 0 ]; then
    offenders=$((offenders + 1))
    {
      echo "runner-isolated: $file is pull_request-triggered and names a self-hosted runner:"
      printf '    %s\n' "${hits[@]}"
    } >&2
  fi
done

if [ "$offenders" -gt 0 ]; then
  cat >&2 <<EOF
runner-isolated: $offenders offending workflow file(s). A pull_request
  workflow runs the PR branch's code; from a fork that code is unreviewed,
  and a self-hosted runner would execute it on our own hardware, inside
  our own network. The unblock is to SPLIT THE WORKFLOW: PR-triggered
  checks in one file on hosted runners, self-hosted work behind
  push/dispatch triggers in another — the shape incubator's pr-checks.yml
  and deploy.yml already have. The rule is file-level on purpose (this
  script's header): a file mixing the two is one editing mistake away
  from being the real bug.
EOF
  exit 1
fi

echo "runner-isolated: ${#files[@]} workflow file(s) scanned under '$workflows_dir' — no pull_request-triggered work on a self-hosted runner"
