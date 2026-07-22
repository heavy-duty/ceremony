#!/usr/bin/env bash
# Contract tests for actions/changelog-monotonic (issue #6). Unlike the
# armed guard's two-file trees, every containment case here needs a real
# constructed git repo — "a heading disappeared" is a property of a DIFF,
# so the fixture is a history: base commit, mutation commit, compare. The
# uniqueness cases deliberately run WITHOUT usable history, because running
# before anything history-dependent is the box#143 lesson under test.
# set -u, not -e: failing commands are behavior for the harness to inspect.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=test/harness.sh
. "$ROOT/test/harness.sh"

SCRIPT="$ROOT/actions/changelog-monotonic/changelog-monotonic.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# repo <name> — a git repo whose first commit holds the changelog arriving
# on stdin, with a 'base' branch pinned there. Later mutations move HEAD;
# 'base' stays put, standing in for origin/main.
repo() {
  local dir="$TMP/$1"
  mkdir -p "$dir"
  git -C "$dir" init -q -b main
  git -C "$dir" config user.email ci@example.invalid
  git -C "$dir" config user.name ci
  cat >"$dir/CHANGELOG.md"
  git -C "$dir" add CHANGELOG.md
  git -C "$dir" commit -qm base
  git -C "$dir" branch base
}

# mutate <name> — replace the repo's changelog with stdin and commit on HEAD.
mutate() {
  local dir="$TMP/$1"
  cat >"$dir/CHANGELOG.md"
  git -C "$dir" commit -qam mutate
}

run() { local dir="$1"; shift; (cd "$TMP/$dir" && bash "$SCRIPT" "$@"); }
run_strict() { local dir="$1"; shift; (cd "$TMP/$dir" && CHANGELOG_MONOTONIC_STRICT=1 bash "$SCRIPT" "$@"); }

# The shared base shape: an armed changelog with two shipped releases.
base_changelog() {
  cat <<'EOF'
# Changelog

## Unreleased

## 0.8.0 — 2026-07-19

- Shipped entry.

## 0.7.0 — 2026-07-01

- Older entry.
EOF
}

# --- the documented flow passes ----------------------------------------------

repo insert-above < <(base_changelog)
mutate insert-above <<'EOF'
# Changelog

## Unreleased

### Fixed

- **A new entry, inserted above.**

## 0.8.0 — 2026-07-19

- Shipped entry.

## 0.7.0 — 2026-07-01

- Older entry.
EOF
check "entry inserted above an existing heading passes" 0 "still present" \
  run insert-above base

repo stamp < <(base_changelog)
mutate stamp <<'EOF'
# Changelog

## Unreleased

## 0.9.0 — 2026-07-22

- The section that was Unreleased, now stamped.

## 0.8.0 — 2026-07-19

- Shipped entry.

## 0.7.0 — 2026-07-01

- Older entry.
EOF
check "the ceremony stamp (adds a heading, removes none) passes" 0 "still present" \
  run stamp base

repo prose-only < <(base_changelog)
mutate prose-only <<'EOF'
# Changelog

## Unreleased

## 0.8.0 — 2026-07-19

- Shipped entry, reworded without touching any heading.

## 0.7.0 — 2026-07-01

- Older entry.
EOF
check "an unrelated heading-less edit passes" 0 "still present" \
  run prose-only base

# --- deletion (the box#122 shape) ----------------------------------------------

# The exact bad edit: the entry's '## Unreleased' block REPLACED the
# '## 0.8.0' heading line, absorbing that release's body.
repo deleted < <(base_changelog)
mutate deleted <<'EOF'
# Changelog

## Unreleased

## Unreleased

### Fixed

- **An entry.**

- Shipped entry.

## 0.7.0 — 2026-07-01

- Older entry.
EOF
check "a deleted shipped heading fails" 1 "DELETES" run deleted base
check "the deletion failure names the missing version" 1 "0.8.0" run deleted base
check "the deletion failure teaches insert-above-never-over" 1 "INSERT above" \
  run deleted base

# --- duplication (the box#118 class) — runs even with NO usable base ----------

repo duped < <(base_changelog)
mutate duped <<'EOF'
# Changelog

## Unreleased

## 0.8.0 — 2026-07-19

### Fixed

- **An entry that belonged under Unreleased.**

## 0.8.0 — 2026-07-19

- Shipped entry.

## 0.7.0 — 2026-07-01

- Older entry.
EOF
check "a duplicated heading on HEAD fails" 1 "DUPLICATE" run duped base
# Ordering is the box#143 lesson: uniqueness must not sit behind the history
# gates. An unresolvable base ref plus STRICT=1 would be a strict failure —
# the duplicate must win, because it needs no history at all.
check "the duplicate fails even when the base ref cannot resolve" 1 "DUPLICATE" \
  run duped no-such-ref
check "the duplicate beats the STRICT failure for the same broken ref" 1 "DUPLICATE" \
  run_strict duped no-such-ref

mkdir -p "$TMP/duped-plain"
cp "$TMP/duped/CHANGELOG.md" "$TMP/duped-plain/CHANGELOG.md"
check "the duplicate fails even outside a git repo entirely" 1 "DUPLICATE" \
  run duped-plain

# --- whole-version set members -------------------------------------------------

# 0.7.0 and 0.7.0-rc1 are distinct members: "renaming" the rc section to the
# bare version deletes the rc heading, and the bare one cannot stand in.
repo rc < <(cat <<'EOF'
# Changelog

## Unreleased

## 0.7.0-rc1 — 2026-06-20

- The candidate's entry.
EOF
)
mutate rc <<'EOF'
# Changelog

## Unreleased

## 0.7.0 — 2026-07-01

- The candidate's entry.
EOF
check "0.7.0 never satisfies a deleted 0.7.0-rc1" 1 "0.7.0-rc1" run rc base

# --- degradation: the loud skip and the STRICT refusal -------------------------

repo no-base < <(base_changelog)
check "base ref missing, STRICT=0: loud skip, exit 0" 0 "SKIPPED" \
  run no-base does-not-exist
check "base ref missing, STRICT=1: hard failure" 1 "FAILURE" \
  run_strict no-base does-not-exist
check "the STRICT failure names the checkout fix, not the script" 1 "fetch-depth: 0" \
  run_strict no-base does-not-exist

mkdir -p "$TMP/plain"
base_changelog >"$TMP/plain/CHANGELOG.md"
check "not a git repo, STRICT=0: loud skip" 0 "not inside a git work tree" \
  run plain
check "not a git repo, STRICT=1: hard failure" 1 "FAILURE" run_strict plain

# --- the honest edges -----------------------------------------------------------

# The commit that first ADDS the changelog: nothing existed at the merge
# base, so nothing could have been deleted.
mkdir -p "$TMP/newfile"
git -C "$TMP/newfile" init -q -b main
git -C "$TMP/newfile" config user.email ci@example.invalid
git -C "$TMP/newfile" config user.name ci
printf 'seed\n' >"$TMP/newfile/README"
git -C "$TMP/newfile" add README
git -C "$TMP/newfile" commit -qm seed
git -C "$TMP/newfile" branch base
base_changelog >"$TMP/newfile/CHANGELOG.md"
git -C "$TMP/newfile" add CHANGELOG.md
git -C "$TMP/newfile" commit -qm add-changelog
check "changelog absent at the merge base passes with the honest notice" 0 \
  "does not exist at the merge base" run newfile base

# Push-to-main shape: the merge base IS HEAD, containment is vacuous by
# construction, and the success line must say which half actually ran.
repo vacuous < <(base_changelog)
check "merge base IS HEAD: vacuous containment named honestly" 0 "vacuous" \
  run vacuous HEAD

check "missing changelog fails" 1 "no such file" run vacuous base NOPE.md

# --- the action's wiring: inputs arrive as env vars ------------------------------

# A non-default changelog name and base env prove the env vars are honored
# the way action.yml passes them, not the defaults.
mkdir -p "$TMP/env-tree"
git -C "$TMP/env-tree" init -q -b main
git -C "$TMP/env-tree" config user.email ci@example.invalid
git -C "$TMP/env-tree" config user.name ci
printf '# Changelog\n\n## 0.1.0 — 2026-07-01\n\n- Entry.\n' >"$TMP/env-tree/NOTES.md"
git -C "$TMP/env-tree" add NOTES.md
git -C "$TMP/env-tree" commit -qm base
git -C "$TMP/env-tree" branch fixture-base
printf '# Changelog\n\n## Unreleased\n\n## 0.1.0 — 2026-07-01\n\n- Entry.\n' >"$TMP/env-tree/NOTES.md"
git -C "$TMP/env-tree" commit -qam mutate
env_tree() {
  (cd "$TMP/env-tree" && \
    CHANGELOG_MONOTONIC_BASE=fixture-base CHANGELOG=NOTES.md CHANGELOG_MONOTONIC_STRICT=1 \
    bash "$SCRIPT")
}
check "env vars drive the script the way action.yml does" 0 "still present" env_tree

summary
