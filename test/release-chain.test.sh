#!/usr/bin/env bash
# The merge door's script chain, composed end-to-end (issue #9): facts →
# decide → notes against a constructed fixture ceremony, exactly the way
# release.yml wires them (facts' $GITHUB_OUTPUT lines become decide's env;
# the notes come from the one canonical extractor). facts.test.sh proves the
# fact rows and decide's own suite proves the table; this file proves the
# HANDOFF between them. Also run by release-exercise.yml on dispatch. set
# -u, not -e: failing commands are behavior for the harness to inspect.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=test/harness.sh
. "$ROOT/test/harness.sh"

FACTS="$ROOT/lib/facts.sh"
DECIDE="$ROOT/lib/decide.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# A gh stub for the one API fact the ceremony path needs: the merged,
# release-labeled PR behind the commit.
mkdir -p "$TMP/stub"
cat >"$TMP/stub/gh" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = api ]; then echo true; exit 0; fi
echo "gh stub: unexpected call: gh $*" >&2
exit 97
EOF
chmod +x "$TMP/stub/gh"

# The fixture: a base tree at 0.6.9-dev with an armed changelog, then the
# ceremony merge — VERSION bumped bare, Unreleased stamped, re-armed above.
git init -q "$TMP/repo"
git -C "$TMP/repo" config user.email fixture@example.invalid
git -C "$TMP/repo" config user.name fixture

printf '0.6.9-dev\n' >"$TMP/repo/VERSION"
cat >"$TMP/repo/CHANGELOG.md" <<'EOF'
# Changelog

## Unreleased

- The entry this release ships.

## 0.6.8 — 2026-07-01

- An older entry.
EOF
git -C "$TMP/repo" add VERSION CHANGELOG.md
git -C "$TMP/repo" commit -qm "base"
BASE_SHA="$(git -C "$TMP/repo" rev-parse HEAD)"

printf '0.7.0\n' >"$TMP/repo/VERSION"
cat >"$TMP/repo/CHANGELOG.md" <<'EOF'
# Changelog

## Unreleased

## 0.7.0 — 2026-07-21

- The entry this release ships.

## 0.6.8 — 2026-07-01

- An older entry.
EOF
git -C "$TMP/repo" add VERSION CHANGELOG.md
git -C "$TMP/repo" commit -qm "release: 0.7.0"
MERGE_SHA="$(git -C "$TMP/repo" rev-parse HEAD)"

# chain <merge_sha> <event_before> — facts, then decide fed from facts'
# output lines, then the notes extraction, printing each stage's result.
chain() {
  (
    cd "$TMP/repo" || exit 1
    facts_out="$(env PATH="$TMP/stub:$PATH" GITHUB_REPOSITORY=fixture/fixture \
      GH_TOKEN=stub VERSION_SOURCE=file MERGE_SHA="$1" EVENT_BEFORE="$2" \
      bash "$FACTS")" || exit 1
    printf '%s\n' "$facts_out"
    ver="$(printf '%s\n' "$facts_out" | awk -F= '$1 == "ver" { print $2 }')"
    base_ver="$(printf '%s\n' "$facts_out" | awk -F= '$1 == "base_ver" { print $2 }')"
    released="$(printf '%s\n' "$facts_out" | awk -F= '$1 == "released" { print $2 }')"
    labeled="$(printf '%s\n' "$facts_out" | awk -F= '$1 == "labeled" { print $2 }')"
    decide_out="$(env VER="$ver" BASE_VER="$base_ver" RELEASED="$released" \
      LABELED="$labeled" bash "$DECIDE")" || exit 1
    printf '%s\n' "$decide_out"
    case "$decide_out" in
      *ceremony=yes*)
        # shellcheck source=lib/changelog.sh
        . "$ROOT/lib/changelog.sh"
        diagnosis="$(changelog_section_problem CHANGELOG.md "$ver")" || {
          printf 'chain: %s\n' "$diagnosis" >&2
          exit 1
        }
        notes="$(changelog_section CHANGELOG.md "$ver")"
        printf 'notes: %s\n' "$notes"
        ;;
    esac
  )
}

check "the ceremony merge decides ceremony=yes" 0 "ceremony=yes" \
  chain "$MERGE_SHA" "$BASE_SHA"
check "the notes are the stamped section's prose" 0 \
  "notes: - The entry this release ships." chain "$MERGE_SHA" "$BASE_SHA"

# The same ceremony facts with an entry-less stamped section must stop at the
# notes door, before any tag or release mutation could run.
git -C "$TMP/repo" reset -q --hard "$BASE_SHA"
printf '0.7.0\n' >"$TMP/repo/VERSION"
cat >"$TMP/repo/CHANGELOG.md" <<'EOF'
# Changelog

## Unreleased

## 0.7.0 — 2026-07-21

### Added

## 0.6.8 — 2026-07-01

- An older entry.
EOF
git -C "$TMP/repo" add VERSION CHANGELOG.md
git -C "$TMP/repo" commit -qm "release: entry-less 0.7.0"
EMPTY_MERGE_SHA="$(git -C "$TMP/repo" rev-parse HEAD)"
check "the notes door refuses an entry-less stamped section" 1 \
  "section '0.7.0' has no entries" chain "$EMPTY_MERGE_SHA" "$BASE_SHA"

git -C "$TMP/repo" reset -q --hard "$MERGE_SHA"

# The same chain on an ordinary merge: -dev, unchanged — a green NOTICE
# no-op that never consults the API (the stub would refuse a release view).
printf 'ordinary work\n' >"$TMP/repo/notes.txt"
git -C "$TMP/repo" add notes.txt
git -C "$TMP/repo" commit -qm "ordinary work"
WORK_SHA="$(git -C "$TMP/repo" rev-parse HEAD)"
printf '0.7.1-dev\n' >"$TMP/repo/VERSION"
git -C "$TMP/repo" add VERSION
git -C "$TMP/repo" commit -qm "chore: bump main to 0.7.1-dev"
BUMP_SHA="$(git -C "$TMP/repo" rev-parse HEAD)"
printf 'more ordinary work\n' >"$TMP/repo/notes.txt"
git -C "$TMP/repo" add notes.txt
git -C "$TMP/repo" commit -qm "more ordinary work"
WORK2_SHA="$(git -C "$TMP/repo" rev-parse HEAD)"

check "the post-release bump decides ceremony=no" 0 "ceremony=no" \
  chain "$BUMP_SHA" "$WORK_SHA"
check "an ordinary -dev merge decides ceremony=no" 0 "ceremony=no" \
  chain "$WORK2_SHA" "$BUMP_SHA"

summary
