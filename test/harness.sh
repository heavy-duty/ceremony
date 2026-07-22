#!/usr/bin/env bash
# Sourced assertion helpers. Tests deliberately use set -u, not set -e:
# failing commands are behavior for the harness to inspect.

PASS=0
FAIL=0

# check <desc> <want_exit> <want_substr> <cmd...>
check() {
  local desc="$1" want="$2" substring="$3"
  shift 3
  local output rc

  output="$("$@" 2>&1)"
  rc=$?
  if [ "$rc" -ne "$want" ]; then
    echo "FAIL: $desc — exit $rc, wanted $want"
    printf '%s\n' "$output" | sed 's/^/    /'
    FAIL=$((FAIL + 1))
    return
  fi
  if [ -n "$substring" ] && ! printf '%s' "$output" | grep -qF -e "$substring"; then
    echo "FAIL: $desc — output missing '$substring'"
    printf '%s\n' "$output" | sed 's/^/    /'
    FAIL=$((FAIL + 1))
    return
  fi
  echo "ok: $desc"
  PASS=$((PASS + 1))
}

summary() {
  printf '%d passed, %d failed\n' "$PASS" "$FAIL"
  [ "$FAIL" -eq 0 ]
}

