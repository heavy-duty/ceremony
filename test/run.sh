#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
shopt -s nullglob
tests=("$ROOT"/test/*.test.sh)

printf 'test: discovered %d test files\n' "${#tests[@]}"
if [ "${#tests[@]}" -eq 0 ]; then
  echo "test: 0 tests — nothing to run"
  exit 0
fi

passed=0
failed=0
for test_file in "${tests[@]}"; do
  printf '\n==> %s\n' "${test_file#"$ROOT"/}"
  if bash "$test_file"; then
    passed=$((passed + 1))
  else
    failed=$((failed + 1))
  fi
done

printf '\ntest files: %d passed, %d failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]

