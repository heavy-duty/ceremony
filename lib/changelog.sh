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
