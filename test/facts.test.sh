#!/usr/bin/env bash
# Contract tests for lib/facts.sh (issue #9) — the merge door's impure half.
# Constructed git repos stand in for the consumer checkout, and a gh stub on
# PATH stands in for the API, so every fact row is proven offline —
# including the rows that must NOT touch the API at all (the stub's default
# mode fails the test if gh is called). set -u, not -e: failing commands are
# behavior for the harness to inspect.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=test/harness.sh
. "$ROOT/test/harness.sh"

FACTS="$ROOT/lib/facts.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

ZEROS="0000000000000000000000000000000000000000"

# The gh stub: behavior selected per call site by GH_STUB. The default
# refuses — the -dev rows and every ordinary merge must never call the API.
mkdir -p "$TMP/stub"
cat >"$TMP/stub/gh" <<'EOF'
#!/usr/bin/env bash
case "${GH_STUB:-none}" in
  labeled-yes | labeled-no)
    if [ "$1" != api ]; then
      echo "gh stub: expected an api call, got: gh $*" >&2
      exit 97
    fi
    [ "${GH_STUB}" = labeled-yes ] && echo true || echo false
    ;;
  released-yes | released-no)
    if [ "$1" != release ]; then
      echo "gh stub: expected a release call, got: gh $*" >&2
      exit 97
    fi
    [ "${GH_STUB}" = released-yes ] && exit 0 || exit 1
    ;;
  *)
    echo "gh stub: gh must not be called in this state (gh $*)" >&2
    exit 97
    ;;
esac
EOF
chmod +x "$TMP/stub/gh"

# repo <name> — a fixture git repo; commit <name> <msg> [file content...]
repo() {
  git init -q "$TMP/$1"
  git -C "$TMP/$1" config user.email fixture@example.invalid
  git -C "$TMP/$1" config user.name fixture
}

# commit <repo> <file> <content> — write one file, commit, print the sha.
commit() {
  printf '%s\n' "$3" >"$TMP/$1/$2"
  git -C "$TMP/$1" add "$2"
  git -C "$TMP/$1" commit -qm "set $2"
  git -C "$TMP/$1" rev-parse HEAD
}

# facts_in <repo> <env assignments...> — run facts.sh inside the fixture
# with the stub first on PATH.
facts_in() {
  local dir="$1"
  shift
  (cd "$TMP/$dir" \
    && env PATH="$TMP/stub:$PATH" GITHUB_REPOSITORY=fixture/fixture GH_TOKEN=stub \
      "$@" bash "$FACTS")
}

# --- the ceremony transition (bare, changed → labeled consulted) -------------

repo ceremony
base_sha="$(commit ceremony VERSION 0.6.9-dev)"
head_sha="$(commit ceremony VERSION 0.7.0)"

check "transition: ver is the head's" 0 "ver=0.7.0" \
  facts_in ceremony VERSION_SOURCE=file MERGE_SHA="$head_sha" EVENT_BEFORE="$base_sha" GH_STUB=labeled-yes
check "transition: base_ver is the base's" 0 "base_ver=0.6.9-dev" \
  facts_in ceremony VERSION_SOURCE=file MERGE_SHA="$head_sha" EVENT_BEFORE="$base_sha" GH_STUB=labeled-yes
check "transition: labeled=yes from the API" 0 "labeled=yes" \
  facts_in ceremony VERSION_SOURCE=file MERGE_SHA="$head_sha" EVENT_BEFORE="$base_sha" GH_STUB=labeled-yes
# The quoted stderr summary is the emptiness assertion: released='' can
# only appear when the API was genuinely skipped (a call would have set
# yes/no, or tripped the stub's default refusal).
check "transition: released stays empty (not consulted)" 0 "released=''" \
  facts_in ceremony VERSION_SOURCE=file MERGE_SHA="$head_sha" EVENT_BEFORE="$base_sha" GH_STUB=labeled-yes
check "transition: labeled=no from the API" 0 "labeled=no" \
  facts_in ceremony VERSION_SOURCE=file MERGE_SHA="$head_sha" EVENT_BEFORE="$base_sha" GH_STUB=labeled-no

# event.before all-zeros (branch-create push) and empty (non-push caller)
# both fall back to the head's first parent (#1 constraint 10).
check "all-zeros event.before falls back to the first parent" 0 "base_ver=0.6.9-dev" \
  facts_in ceremony VERSION_SOURCE=file MERGE_SHA="$head_sha" EVENT_BEFORE="$ZEROS" GH_STUB=labeled-yes
check "empty event.before falls back to the first parent" 0 "base_ver=0.6.9-dev" \
  facts_in ceremony VERSION_SOURCE=file MERGE_SHA="$head_sha" EVENT_BEFORE= GH_STUB=labeled-yes

# --- the -dev rows: no API call, ever (the stub would exit 97) ---------------

repo dev-work
dev_base="$(commit dev-work VERSION 0.7.1-dev)"
dev_head="$(commit dev-work notes.txt "ordinary work")"

check "-dev unchanged: no API calls made" 0 "base_ver=0.7.1-dev" \
  facts_in dev-work VERSION_SOURCE=file MERGE_SHA="$dev_head" EVENT_BEFORE="$dev_base"
check "-dev unchanged: released and labeled stay empty" 0 "released='' labeled=''" \
  facts_in dev-work VERSION_SOURCE=file MERGE_SHA="$dev_head" EVENT_BEFORE="$dev_base"

repo dev-bump
bump_base="$(commit dev-bump VERSION 0.7.0)"
bump_head="$(commit dev-bump VERSION 0.7.1-dev)"
check "the post-release bump (bare -> -dev): no API calls" 0 "ver=0.7.1-dev" \
  facts_in dev-bump VERSION_SOURCE=file MERGE_SHA="$bump_head" EVENT_BEFORE="$bump_base"

# --- bare, unchanged → released consulted, labeled skipped -------------------

repo window
win_base="$(commit window VERSION 0.7.0)"
win_head="$(commit window notes.txt "post-release window work")"

check "bare unchanged: released=yes from the API" 0 "released=yes" \
  facts_in window VERSION_SOURCE=file MERGE_SHA="$win_head" EVENT_BEFORE="$win_base" GH_STUB=released-yes
check "bare unchanged: released=no from the API" 0 "released=no" \
  facts_in window VERSION_SOURCE=file MERGE_SHA="$win_head" EVENT_BEFORE="$win_base" GH_STUB=released-no
check "bare unchanged: labeled stays empty (not consulted)" 0 "labeled=''" \
  facts_in window VERSION_SOURCE=file MERGE_SHA="$win_head" EVENT_BEFORE="$win_base" GH_STUB=released-yes

# --- a base tree with no version source at all -------------------------------

# The merge that ADDS the version machinery (a consumer's adoption PR).
# "(none)" is not a version, so decide still governs: -dev head is work,
# bare head still demands the label. Nothing releases silently.
repo adoption
adopt_base="$(commit adoption README.md "pre-ceremony tree")"
adopt_head="$(commit adoption VERSION 0.1.0-dev)"

check "absent-at-base reads as (none), -dev head consults no API" 0 "base_ver=(none)" \
  facts_in adoption VERSION_SOURCE=file MERGE_SHA="$adopt_head" EVENT_BEFORE="$adopt_base"

repo adoption-bare
adoptb_base="$(commit adoption-bare README.md "pre-ceremony tree")"
adoptb_head="$(commit adoption-bare VERSION 0.1.0)"
check "absent-at-base with a bare head still asks for the label" 0 "labeled=yes" \
  facts_in adoption-bare VERSION_SOURCE=file MERGE_SHA="$adoptb_head" EVENT_BEFORE="$adoptb_base" GH_STUB=labeled-yes

# --- a root commit: no base tree at all (the repository's first push) --------

# The first push to main IS a branch-create push (event.before all-zeros)
# whose head has no first parent — there is no base, and the honest fact is
# "(none)", not an exit-128 death at rev-parse. Both 0.2.0 drills hit the
# death independently (#134). The -dev row consults no API (stub default),
# which also asserts the no-base path runs no base fetch/show at all.
repo greenfield
green_head="$(commit greenfield VERSION 0.1.0-dev)"

check "root commit, all-zeros event.before: base_ver=(none)" 0 "base_ver=(none)" \
  facts_in greenfield VERSION_SOURCE=file MERGE_SHA="$green_head" EVENT_BEFORE="$ZEROS"
check "root commit, empty event.before: base_ver=(none)" 0 "base_ver=(none)" \
  facts_in greenfield VERSION_SOURCE=file MERGE_SHA="$green_head" EVENT_BEFORE=

repo greenfield-bare
greenb_head="$(commit greenfield-bare VERSION 0.1.0)"
check "bare root commit still establishes labeled, so decide can refuse" 0 "labeled=no" \
  facts_in greenfield-bare VERSION_SOURCE=file MERGE_SHA="$greenb_head" EVENT_BEFORE="$ZEROS" GH_STUB=labeled-no

# The D2 pin: "no first parent" is detected, never inferred from a failed
# command — an unresolvable MERGE_SHA is a loud death, not "(none)". A
# `|| true` around the fallback would pass every case above and fail here.
BAD_SHA="1111111111111111111111111111111111111111"
check "an unresolvable MERGE_SHA still dies loudly" 128 "bad object" \
  facts_in greenfield VERSION_SOURCE=file MERGE_SHA="$BAD_SHA" EVENT_BEFORE="$ZEROS"
bad_out="$(facts_in greenfield VERSION_SOURCE=file MERGE_SHA="$BAD_SHA" EVENT_BEFORE="$ZEROS" 2>&1)"
if printf '%s' "$bad_out" | grep -qF "base_ver=(none)"; then
  echo "FAIL: an unresolvable MERGE_SHA must not be reported as base_ver=(none)"
  printf '%s\n' "$bad_out" | sed 's/^/    /'
  FAIL=$((FAIL + 1))
else
  echo "ok: an unresolvable MERGE_SHA is not reported as base_ver=(none)"
  PASS=$((PASS + 1))
fi

# --- the package-json backend ------------------------------------------------

repo pkg
pkg_base="$(commit pkg package.json '{ "name": "fixture", "version": "1.1.9-dev" }')"
pkg_head="$(commit pkg package.json '{ "name": "fixture", "version": "1.2.0" }')"

check "package-json: head version via node" 0 "ver=1.2.0" \
  facts_in pkg VERSION_SOURCE=package-json MERGE_SHA="$pkg_head" EVENT_BEFORE="$pkg_base" GH_STUB=labeled-yes
check "package-json: base version via node" 0 "base_ver=1.1.9-dev" \
  facts_in pkg VERSION_SOURCE=package-json MERGE_SHA="$pkg_head" EVENT_BEFORE="$pkg_base" GH_STUB=labeled-yes

# --- refusals ----------------------------------------------------------------

check "missing VERSION_SOURCE refuses" 1 "VERSION_SOURCE is required" \
  facts_in ceremony MERGE_SHA="$head_sha" EVENT_BEFORE="$base_sha"
check "missing MERGE_SHA refuses" 1 "MERGE_SHA is required" \
  facts_in ceremony VERSION_SOURCE=file EVENT_BEFORE="$base_sha"
check "unknown backend refuses" 1 "unknown VERSION_SOURCE" \
  facts_in ceremony VERSION_SOURCE=carrier-pigeon MERGE_SHA="$head_sha" EVENT_BEFORE="$base_sha"

repo no-version
nv_base="$(commit no-version README.md "a tree")"
nv_head="$(commit no-version README.md "with no version at the head either")"
check "no version at the head fails loudly" 1 "no such file" \
  facts_in no-version VERSION_SOURCE=file MERGE_SHA="$nv_head" EVENT_BEFORE="$nv_base"

summary
