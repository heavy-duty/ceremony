#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

mapfile -t files < <(
  # actionlint validates workflow syntax, not composite action metadata;
  # feeding action.yml to it misclassifies the file as a workflow.
  git ls-files '.github/workflows/*.yml' | sort -u
)

[ "${#files[@]}" -gt 0 ] || {
  echo "actionlint-all: found no workflow or action files — the sweep is broken" >&2
  exit 1
}

printf 'actionlint: linting %d files\n' "${#files[@]}"
printf '  %s\n' "${files[@]}"
actionlint "${files[@]}"
