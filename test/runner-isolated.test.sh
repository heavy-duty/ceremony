#!/usr/bin/env bash
# Contract tests for actions/runner-isolated (issue #58). Constructed
# fixture trees — a dir holding a workflows directory, not git repos —
# the same discipline as the guards beside it. set -u, not -e: failing
# commands are behavior for the harness to inspect.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=test/harness.sh
. "$ROOT/test/harness.sh"

SCRIPT="$ROOT/actions/runner-isolated/runner-isolated.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# The guard reads the consumer's tree at its working directory, so every
# case runs from inside a constructed fixture tree.
in_tree() {
  local dir="$1"
  shift
  (cd "$TMP/$dir" && bash "$SCRIPT" "$@")
}

# wf <tree> <file> — write .github/workflows/<file> in the tree from stdin.
wf() {
  mkdir -p "$TMP/$1/.github/workflows"
  cat >"$TMP/$1/.github/workflows/$2"
}

# --- the rows that must FAIL: they are the point of this file ----------------

# 1: block-form trigger + inline-list runner — incubator's deploy.yml
# shape with the one edit that would make it the bug.
wf block-list a.yml <<'YAML'
name: deploy checks
on:
  pull_request:
    types: [opened]
jobs:
  deploy:
    runs-on: [self-hosted, ci-runner]
    steps:
      - run: echo deploy
YAML
check "on: block + runs-on inline list fails" 1 "self-hosted" \
  in_tree block-list
check "failure names the offending file" 1 "a.yml" in_tree block-list
check "failure names the offending runs-on line" 1 "runs-on: [self-hosted, ci-runner]" \
  in_tree block-list

# 2: inline-list trigger + scalar runner.
wf inline-trigger a.yml <<'YAML'
name: ci
on: [push, pull_request]
jobs:
  build:
    runs-on: self-hosted
    steps:
      - run: echo build
YAML
check "on: inline list + runs-on scalar fails" 1 "self-hosted" \
  in_tree inline-trigger

# 3: scalar trigger + self-hosted — and a .yaml extension, so the second
# glob leg is load-bearing in at least one case.
wf scalar-trigger a.yaml <<'YAML'
name: ci
on: pull_request
jobs:
  build:
    runs-on: self-hosted
    steps:
      - run: echo build
YAML
check "on: scalar + self-hosted fails, .yaml extension scanned" 1 "a.yaml" \
  in_tree scalar-trigger

# 4: the quoted key — YAML 1.1 parses bare `on` as a boolean, so some
# repos quote it; a guard that missed this form would silently pass the
# file it most needs to read.
wf quoted-on a.yml <<'YAML'
name: ci
"on":
  pull_request:
jobs:
  build:
    runs-on: self-hosted
    steps:
      - run: echo build
YAML
check "quoted \"on\": key + self-hosted fails" 1 "self-hosted" \
  in_tree quoted-on

# 5: pull_request_target is the same threat with a scarier token.
wf target a.yml <<'YAML'
name: ci
on:
  pull_request_target:
jobs:
  build:
    runs-on: self-hosted
    steps:
      - run: echo build
YAML
check "pull_request_target + self-hosted fails" 1 "self-hosted" \
  in_tree target

# 6: two jobs in one file — a PR-triggered hosted check AND a self-hosted
# job. Pins the file-level decision (#58 §3): a later "fix" to job
# granularity must be a deliberate change, not a silent one.
wf mixed-jobs a.yml <<'YAML'
name: ci
on:
  pull_request:
jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - run: echo check
  deploy:
    runs-on: [self-hosted, ci-runner]
    steps:
      - run: echo deploy
YAML
check "file-level rule: hosted PR check + self-hosted job in one file fails" 1 \
  "self-hosted" in_tree mixed-jobs

# The block-sequence runner — the same-line rule alone would pass this
# file, and a false negative is the one defect this guard is not allowed
# to have (the script header's why).
wf block-seq a.yml <<'YAML'
name: ci
on:
  pull_request:
jobs:
  deploy:
    runs-on:
      - self-hosted
      - ci-runner
    steps:
      - run: echo deploy
YAML
check "block-sequence runs-on: - self-hosted fails" 1 "self-hosted" \
  in_tree block-seq

# 11: multiple offenders across two files — BOTH named, not just the first.
wf two-files a.yml <<'YAML'
name: one
on: pull_request
jobs:
  a:
    runs-on: self-hosted
    steps:
      - run: echo a
YAML
wf two-files b.yml <<'YAML'
name: two
on: pull_request
jobs:
  b:
    runs-on: [self-hosted, other]
    steps:
      - run: echo b
YAML
check "two offending files: the first is named" 1 "a.yml" in_tree two-files
check "two offending files: the second is named too" 1 "b.yml" in_tree two-files

# --- the rows that must PASS: the legal shapes stay legal --------------------

# 7: push-only + self-hosted — incubator's deploy.yml, which must stay
# legal.
wf push-deploy deploy.yml <<'YAML'
name: deploy
on:
  push:
    branches: [main]
jobs:
  deploy:
    runs-on: [self-hosted, ci-runner]
    steps:
      - run: echo deploy
YAML
check "push-only + self-hosted passes (deploy.yml's shape)" 0 "1 workflow file" \
  in_tree push-deploy

# The block-sequence window with no PR trigger: the window logic must not
# widen the rule past its two conditions.
wf push-block-seq deploy.yml <<'YAML'
name: deploy
on:
  push:
    branches: [main]
jobs:
  deploy:
    runs-on:
      - self-hosted
    steps:
      - run: echo deploy
YAML
check "push-only + block-sequence self-hosted passes" 0 "1 workflow file" \
  in_tree push-block-seq

# 8: PR trigger on a hosted runner — incubator's pr-checks.yml.
wf pr-hosted checks.yml <<'YAML'
name: checks
on:
  pull_request:
jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - run: echo check
YAML
check "pull_request + ubuntu-latest passes (pr-checks.yml's shape)" 0 \
  "1 workflow file" in_tree pr-hosted

# 9: self-hosted in a comment only — prose is not the bug; incubator's
# pr-checks.yml header is exactly this prose.
wf comment-only checks.yml <<'YAML'
name: checks
# Unreviewed branch code must never reach the self-hosted deploy runner.
on:
  pull_request:
jobs:
  check:
    # not: runs-on: self-hosted
    runs-on: ubuntu-latest
    steps:
      - run: echo check
YAML
check "self-hosted in comments only passes" 0 "1 workflow file" \
  in_tree comment-only

# 10: an empty workflows dir, and no workflows dir at all — both pass; a
# guard that fails on absence is a guard nobody adopts.
mkdir -p "$TMP/empty-dir/.github/workflows"
check "empty workflows dir passes" 0 "0 workflow files" in_tree empty-dir
mkdir -p "$TMP/no-dir"
check "missing workflows dir passes" 0 "no workflows directory" in_tree no-dir

# 12: a schedule trigger with self-hosted and no PR trigger — the runner
# half alone is not the offence.
wf scheduled nightly.yml <<'YAML'
name: nightly
on:
  schedule:
    - cron: '0 3 * * *'
jobs:
  sweep:
    runs-on: [self-hosted, ci-runner]
    steps:
      - run: echo sweep
YAML
check "schedule + self-hosted, no PR trigger, passes" 0 "1 workflow file" \
  in_tree scheduled

# The trigger-block span: pull_request below the on: block (here, a step
# name in jobs:) is not a trigger. Guards the block-end detection.
wf pr-elsewhere build.yml <<'YAML'
name: build
on:
  push:
    branches: [main]
jobs:
  build:
    runs-on: [self-hosted, ci-runner]
    steps:
      - name: mention pull_request in a step name
        run: echo build
YAML
check "pull_request outside the on: block is not a trigger" 0 \
  "1 workflow file" in_tree pr-elsewhere

# --- a non-default workflows dir, as arg and as the action's env var ---------

mkdir -p "$TMP/alt-dir/ci-flows"
cat >"$TMP/alt-dir/ci-flows/a.yml" <<'YAML'
name: ci
on: pull_request
jobs:
  a:
    runs-on: self-hosted
    steps:
      - run: echo a
YAML
check "a non-default workflows dir is honored as an argument" 1 "ci-flows/a.yml" \
  in_tree alt-dir ci-flows

# A non-default dir proves the env var is honored, not the default —
# the same wiring proof drill-recorded's suite carries.
env_tree() {
  (cd "$TMP/alt-dir" && WORKFLOWS_DIR=ci-flows bash "$SCRIPT")
}
check "the env var drives the script the way action.yml does" 1 \
  "ci-flows/a.yml" env_tree

# --- ceremony's own tree — the same tree self-guards runs against ------------

# A future workflow change that breaks this guard's parsing should show
# up as a unit-test failure, not only as a red CI job.
own_tree() {
  (cd "$ROOT" && bash "$SCRIPT")
}
check "ceremony's own .github/workflows passes" 0 "no pull_request-triggered work" \
  own_tree

summary
