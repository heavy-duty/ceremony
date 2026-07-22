#!/usr/bin/env bash
set -euo pipefail

# A glob can quietly stop guarding when a script moves under a dot-directory
# or loses its extension. Derive the lint set from the tracked tree instead,
# following cast#118's fix, and print it so a shrinking sweep is visible.
cd "$(git rev-parse --show-toplevel)"

mapfile -t files < <(
  {
    git ls-files '*.sh'
    git ls-files | while IFS= read -r file; do
      case "$file" in *.sh) continue ;; esac
      [ -f "$file" ] || continue
      IFS= read -r line <"$file" || [ -n "$line" ] || continue
      case "$line" in '#!'*) ;; *) continue ;; esac
      interpreter="${line#\#!}"
      interpreter="${interpreter%% -*}"
      interpreter="${interpreter##*[ /]}"
      case "$interpreter" in sh | bash | dash | ksh) printf '%s\n' "$file" ;; esac
    done
  } | sort -u
)

[ "${#files[@]}" -gt 0 ] || {
  echo "shellcheck-all: found no shell scripts — the sweep is broken" >&2
  exit 1
}

printf 'shellcheck: linting %d tracked scripts\n' "${#files[@]}"
printf '  %s\n' "${files[@]}"
shellcheck -x ${files[@]}

