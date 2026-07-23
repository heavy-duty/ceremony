#!/usr/bin/env bash
# This is the convergence point for box/cast's executable release-notes.sh
# and rig's sourced release-lib.sh. Both histories matter: the publisher and
# guards must use exactly one definition of a changelog section.
#
# box/cast: https://github.com/heavy-duty/box/blob/a17903f07c83aa18c0f009565e1a5442da6d0827/.github/scripts/release-notes.sh
# rig: https://github.com/heavy-duty/rig/blob/7f8a0e08852837475505f404985a1251a2c3a8a1/.github/scripts/release-lib.sh

# changelog_section <file> <version>
#
# Print the body of exactly one changelog section. The whole second field is
# compared as a string so dots are not regex metacharacters and 0.7.0 can
# never select 0.7.0-rc1. Leading blank padding is omitted; blank lines after
# the body starts are content. Empty output represents either an absent or an
# empty section, which callers deliberately treat as the same refusal.
changelog_section() {
  awk -v ver="$2" '
    /^## / { if (found) exit; found = ($2 == ver); next }
    found && !body && /^[[:space:]]*$/ { next }
    found { body = 1; print }
  ' "$1"
}

# changelog_section_problem <file> <version>
#
# Print the first reason a version section cannot be published. Unreleased is
# a work-in-progress template, so its headings may deliberately be empty.
# A printed problem returns 1; silence returns 0.
changelog_section_problem() {
  local file="$1" ver="$2" notes problem

  if ! awk -v ver="$ver" '/^## / && $2 == ver { found = 1; exit } END { exit !found }' "$file"; then
    printf "no section for '%s'\n" "$ver"
    return 1
  fi

  [ "$ver" = "Unreleased" ] && return 0

  notes="$(changelog_section "$file" "$ver")"
  if ! printf '%s\n' "$notes" | awk '/^[[:space:]]*[-*][[:space:]]/ { found = 1; exit } END { exit !found }'; then
    printf "section '%s' has no entries — a heading is not an entry\n" "$ver"
    return 1
  fi

  problem="$(
    printf '%s\n' "$notes" | awk '
      /^### / {
        if (heading != "" && !entry) {
          reported = 1
          print heading
          exit
        }
        heading = $0
        entry = 0
        next
      }
      heading != "" && /^[[:space:]]*[-*][[:space:]]/ { entry = 1 }
      END {
        if (!reported && heading != "" && !entry) print heading
      }
    '
  )"
  if [ -n "$problem" ]; then
    printf "section '%s' has an empty heading: '%s'\n" "$ver" "$problem"
    return 1
  fi
}
