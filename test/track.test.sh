#!/usr/bin/env bash
# Contract tests for lib/track.sh (#618): the release track's path and tag
# prefix. The default track — "." and "" — must be the identity everywhere,
# since every repository that predates tracks calls with it.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=test/harness.sh
. "$ROOT/test/harness.sh"

run() { # run <function> <args...> — call a track.sh function in a subshell
  bash -c '. "$1/lib/track.sh"; shift; "$@"' _ "$ROOT" "$@"
}

check "an empty path is the default track" 0 "." run track_path_normalize ""
check "'.' is the default track" 0 "." run track_path_normalize .
check "'./' is the default track" 0 "." run track_path_normalize ./
check "a leading './' and trailing '/' are dropped" 0 "apps/admin" \
  run track_path_normalize ./apps/admin/
check_absent "the canonical form carries no trailing slash" 0 "apps/admin/" \
  run track_path_normalize apps/admin//
check "an absolute path is refused" 1 "is absolute" \
  run track_path_normalize /apps/admin
check "a '..' segment is refused" 1 "'.' or '..' segment" \
  run track_path_normalize apps/../admin
check "a leading '..' is refused" 1 "'.' or '..' segment" \
  run track_path_normalize ../other
check "an inner '.' segment is refused" 1 "'.' or '..' segment" \
  run track_path_normalize apps/./admin
check "an empty inner segment is refused" 1 "empty segment" \
  run track_path_normalize apps//admin

check "the default track's file is the bare name" 0 "CHANGELOG.md" \
  run track_file . CHANGELOG.md
check_absent "the default track's file carries no './'" 0 "./" \
  run track_file . CHANGELOG.md
check "a track's file is under its directory" 0 "apps/admin/changelog.d" \
  run track_file apps/admin changelog.d

check "an empty prefix is the default track" 0 "" run track_prefix_check ""
check "a word and a dash is a prefix" 0 "" run track_prefix_check admin-
check "a slash is allowed (tag namespaces)" 0 "" run track_prefix_check site/v
check "a leading digit is refused" 1 "must start with a letter" \
  run track_prefix_check 2-
check "a glob character is refused" 1 "must start with a letter" \
  run track_prefix_check 'admin-*'
check "a space is refused" 1 "must start with a letter" \
  run track_prefix_check 'admin '

check "the default track's tag is the bare version" 0 "2.1.0" run track_tag "" 2.1.0
check "a track's tag is the prefix and the version" 0 "admin-2.1.0-rc1" \
  run track_tag admin- 2.1.0-rc1

summary
