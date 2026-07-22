#!/usr/bin/env bash
set -euo pipefail

# docs-sync.sh [--check|--fix] [--source <dir>] — materialize and verify the
# `.ceremony/` doctrine mirror in a governed repo. Run from the consumer's
# repo root (the action runs after the consumer's own checkout, like every
# guard).
#
# WHY A COPY EXISTS AT ALL (the reference-vs-mirror rationale — issue #19,
# PR #17's consumption model): workflows and actions are consumed BY
# REFERENCE — GitHub fetches them from the pinned ref at run time, so no
# copy ever exists in a consumer, and nothing can drift. Documents have no
# such runtime. A document's only "runtime" is an agent reading the working
# tree of the repo it stands in, and a doc that requires a cross-repo fetch
# before it governs is a doc that sometimes goes unread. So the agent-facing
# set (the manifest, docs/VENDORED.txt) must exist IN each governed repo's
# tree. Anyone tempted to "simplify" `.ceremony/` back to a pointer at
# heavy-duty/ceremony is reinventing the sometimes-unread doc. The mirror is
# the fix, and this tool is what makes the mirror safe: machine-written
# (--fix), machine-verified (--check, in the consumer's CI on every PR), so
# drift is unrepresentable — the only kind of copy the org allows.
#
# ONE PIN GOVERNS MACHINERY AND DOCTRINE. The ref is read from the
# consumer's .github/workflows/release.yml — the single
# `uses: heavy-duty/ceremony/.github/workflows/release.yml@<ref>` line —
# never from an input or a second config file: a second pin is a second
# thing to bump, and two pins can disagree, which is exactly the drift this
# tool exists to make unrepresentable. Exactly one such line must match;
# zero or several is a refusal that names the file — this tool never
# guesses a ref. Commented-out lines do not count: ceremony's own
# release.yml carries the pin shape inside its header essay, and any
# consumer that pastes a documentation snippet into a comment would
# otherwise appear to have two pins.
#
# THE MIRROR IS EXACT — manifest ∪ `.ceremony/`, nothing else. A drifted
# file, a missing file, an extra file not in the manifest, or no
# `.ceremony/` at all each fails --check with a message naming the offender
# and the fix; --fix writes AND deletes (a manifest removal must remove the
# vendored copy — mirror means mirror, or "extra" files accumulate as
# unverified doctrine).
#
# TWO FILES ARE SPECIAL, both deliberately:
#   * `.ceremony/README.md` is GENERATED here — the machine-managed marker
#     plus where the pin lives — instead of per-file banners, so every
#     vendored file stays byte-identical to its source and the check is a
#     plain cmp, never a strip-the-banner parse.
#   * the consumer's ROOT AGENTS.md is scaffolded once by --fix and never
#     overwritten. Agent harnesses auto-load root AGENTS.md (the cross-agent
#     convention), so the stub is what makes "you are a reviewer here" a
#     sufficient launch prompt — but it is per-repo content the moment the
#     repo edits it, so --check asserts only that it exists.
#
# A file of its own so test/docs-sync.test.sh can drive both modes against
# constructed source and consumer trees. --source <dir> substitutes a local
# ceremony checkout for the tarball fetch: offline tests, and previewing a
# ceremony PR against a consumer before anything is released. The pin is
# still read and validated with --source — a consumer without its one pin
# line has nothing for the mirror to be verified against.

WORKFLOW=".github/workflows/release.yml"
MIRROR=".ceremony"
MANIFEST="docs/VENDORED.txt"
README_NAME="README.md"

die() {
  printf '%s\n' "$@" >&2
  exit 1
}

# Inputs arrive as env vars from action.yml (MODE, SOURCE) or as flags for
# local and test use; flags win.
mode="${MODE:-check}"
source_dir="${SOURCE:-}"
while [ $# -gt 0 ]; do
  case "$1" in
    --check) mode=check ;;
    --fix) mode=fix ;;
    --source)
      [ $# -ge 2 ] || die "docs-sync: --source needs a directory"
      source_dir="$2"
      shift
      ;;
    *) die "docs-sync: unknown argument: $1 (usage: docs-sync.sh [--check|--fix] [--source <dir>])" ;;
  esac
  shift
done
case "$mode" in
  check | fix) ;;
  *) die "docs-sync: unknown mode: '$mode' (check or fix)" ;;
esac

# --- the pin ----------------------------------------------------------------

[ -f "$WORKFLOW" ] || die \
  "docs-sync: no $WORKFLOW — the pin lives there (the single" \
  "  'uses: heavy-duty/ceremony/.github/workflows/release.yml@<ref>' line)." \
  "  Add the release caller before syncing doctrine: the mirror is verified" \
  "  against the pin, and without one there is nothing to verify against."

# A real `uses:` key only — a leading '#' anywhere before it is a comment
# and does not count (see the header: ceremony's own release.yml carries
# the shape in a comment).
mapfile -t pin_lines < <(grep -E \
  '^[[:space:]]*(-[[:space:]]*)?uses:[[:space:]]*heavy-duty/ceremony/\.github/workflows/release\.yml@' \
  "$WORKFLOW" || true)
case "${#pin_lines[@]}" in
  0)
    die "docs-sync: no pin line in $WORKFLOW — expected exactly one" \
      "  'uses: heavy-duty/ceremony/.github/workflows/release.yml@<ref>'," \
      "  found none. This tool never guesses a ref."
    ;;
  1) ;;
  *)
    die "docs-sync: ${#pin_lines[@]} pin lines in $WORKFLOW — exactly one" \
      "  'uses: heavy-duty/ceremony/.github/workflows/release.yml@<ref>' must" \
      "  match, or 'the pin' is ambiguous. This tool never guesses a ref."
    ;;
esac
ref="$(printf '%s\n' "${pin_lines[0]}" | sed -E 's/^.*@//; s/[[:space:]#].*$//')"
[ -n "$ref" ] || die "docs-sync: the pin line in $WORKFLOW carries an empty ref after '@'"

# --- the source tree ----------------------------------------------------------

fetch_tmp=""
# An if, not `&&`: the trap's last status becomes the script's exit code,
# and a bare `[ -n ] && rm` returns 1 whenever there was nothing to clean —
# turning every --source success into a failure.
cleanup() { if [ -n "$fetch_tmp" ]; then rm -rf "$fetch_tmp"; fi; }
trap cleanup EXIT

if [ -n "$source_dir" ]; then
  [ -d "$source_dir" ] || die "docs-sync: --source: no such directory: $source_dir"
  src="$source_dir"
  origin="$source_dir (--source override; pin is heavy-duty/ceremony@$ref)"
else
  # The repo is public: a plain tarball fetch, no auth, no git. Works for a
  # tag, a branch, or a commit SHA alike.
  fetch_tmp="$(mktemp -d)"
  url="https://github.com/heavy-duty/ceremony/archive/${ref}.tar.gz"
  curl -fsSL "$url" | tar -xz --strip-components=1 -C "$fetch_tmp" || die \
    "docs-sync: cannot fetch heavy-duty/ceremony@$ref ($url) —" \
    "  does the pinned ref exist?"
  src="$fetch_tmp"
  origin="heavy-duty/ceremony@$ref"
fi

# --- the manifest -------------------------------------------------------------

# The manifest is read from the SOURCE tree, not the consumer: what gets
# mirrored is decided at the pinned ref, so bumping the pin onto a ref that
# adds or drops a doc re-shapes the mirror in the same PR, with no second
# list to update. It is also the single source of the set — nothing below
# hardcodes a filename.
manifest_file="$src/$MANIFEST"
[ -f "$manifest_file" ] || die \
  "docs-sync: no $MANIFEST in $origin — the manifest is the single source" \
  "  of what gets mirrored; a ref that predates it cannot govern a mirror." \
  "  Bump the pin to a ref that carries it."
mapfile -t manifest < <(grep -v '^[[:space:]]*$' "$manifest_file" || true)
[ "${#manifest[@]}" -gt 0 ] || die \
  "docs-sync: $MANIFEST in $origin is empty — an empty doctrine set is a" \
  "  ceremony bug, not a repo with no rules; refusing to mirror it."
for f in "${manifest[@]}"; do
  case "$f" in
    /* | *..*)
      die "docs-sync: refusing manifest path '$f' — the mirror writes only" \
        "  inside $MIRROR/, and that path escapes it."
      ;;
  esac
  [ -f "$src/$f" ] || die \
    "docs-sync: the manifest names '$f' but $origin has no such file —" \
    "  fix $MANIFEST in heavy-duty/ceremony."
done

in_manifest() {
  local p
  for p in "${manifest[@]}"; do
    [ "$p" = "$1" ] && return 0
  done
  return 1
}

# Every file physically present in the mirror, relative to it. sorted so
# messages come out in a stable order.
mirror_files() {
  find "$MIRROR" -type f | LC_ALL=C sort | while IFS= read -r path; do
    printf '%s\n' "${path#"$MIRROR"/}"
  done
}

# --- the two generated texts ---------------------------------------------------

readme_content() {
  cat <<'EOF'
# .ceremony/ — the vendored doctrine mirror

Machine-managed by heavy-duty/ceremony's `actions/docs-sync`. Never edit
these files here: they are byte-identical copies of
[heavy-duty/ceremony](https://github.com/heavy-duty/ceremony) at this
repository's pinned ref, and CI re-diffs them on every PR — a hand edit
goes red. They are changed in heavy-duty/ceremony, through its own flow,
and arrive here when the pin moves.

The pin lives in `.github/workflows/release.yml` — the single
`uses: heavy-duty/ceremony/.github/workflows/release.yml@<ref>` line. One
pin governs machinery and doctrine alike: bump it and re-sync this mirror
in the same PR (`docs-sync --fix`, or let the red check on the bump PR say
what is stale).
EOF
}

stub_content() {
  cat <<'EOF'
# AGENTS.md — start at .ceremony/

This repository is governed by
[heavy-duty/ceremony](https://github.com/heavy-duty/ceremony). Read
`.ceremony/AGENTS.md` first — it routes you to your role file, vendored
beside it. Repo specifics (the review panel roster, the scope labels, what
a drill means here, code conventions) live in CONTRIBUTING.md.
EOF
}

# --- check ----------------------------------------------------------------------

run_check() {
  local failures=0 f rel
  complain() {
    printf '%s\n' "$@" >&2
    failures=$((failures + 1))
  }

  if [ ! -d "$MIRROR" ]; then
    complain "docs-sync: $MIRROR/ is missing entirely — this tree carries no" \
      "  doctrine mirror. Fix: run docs-sync --fix and commit the result."
  else
    for f in "${manifest[@]}"; do
      if [ ! -f "$MIRROR/$f" ]; then
        complain "docs-sync: $MIRROR/$f is missing from the mirror." \
          "  Fix: run docs-sync --fix."
      elif ! cmp -s "$src/$f" "$MIRROR/$f"; then
        complain "docs-sync: $MIRROR/$f has drifted from $origin." \
          "  Vendored files are never edited in place — they are changed in" \
          "  heavy-duty/ceremony, through its own flow. Fix: run docs-sync --fix" \
          "  (or re-run after bumping the pin, if the drift is a stale pin)."
      fi
    done
    while IFS= read -r rel; do
      [ "$rel" = "$README_NAME" ] && continue
      in_manifest "$rel" && continue
      complain "docs-sync: extra file in the mirror: $MIRROR/$rel — not in the" \
        "  manifest ($MANIFEST). The mirror is exact: everything under" \
        "  $MIRROR/ must be vendored and verified, or it poses as doctrine" \
        "  without being checked. Fix: run docs-sync --fix (it deletes orphans)."
    done < <(mirror_files)
  fi

  # Existence only, content free: the stub is per-repo the moment the repo
  # edits it (see the header).
  [ -f AGENTS.md ] || complain \
    "docs-sync: no root AGENTS.md — the stub that routes agents into" \
    "  $MIRROR/ is missing, so 'you are a reviewer here' has no entry point." \
    "  Fix: run docs-sync --fix (scaffolds it once; edit it freely after)."

  [ "$failures" -eq 0 ] || die "docs-sync: $failures problem(s) — see above."
  echo "docs-sync: $MIRROR/ is an exact mirror of $origin (${#manifest[@]} files)"
}

# --- fix ------------------------------------------------------------------------

run_fix() {
  local changed=0 f rel dest
  note() {
    printf 'docs-sync: %s\n' "$1"
    changed=$((changed + 1))
  }

  mkdir -p "$MIRROR"
  for f in "${manifest[@]}"; do
    dest="$MIRROR/$f"
    if [ ! -f "$dest" ]; then
      mkdir -p "$(dirname "$dest")"
      cp "$src/$f" "$dest"
      note "added $dest"
    elif ! cmp -s "$src/$f" "$dest"; then
      cp "$src/$f" "$dest"
      note "updated $dest"
    fi
  done

  while IFS= read -r rel; do
    [ "$rel" = "$README_NAME" ] && continue
    in_manifest "$rel" && continue
    rm "$MIRROR/$rel"
    note "deleted $MIRROR/$rel (not in the manifest — mirror means mirror)"
  done < <(mirror_files)
  find "$MIRROR" -mindepth 1 -type d -empty -delete

  if [ ! -f "$MIRROR/$README_NAME" ] || ! readme_content | cmp -s - "$MIRROR/$README_NAME"; then
    readme_content >"$MIRROR/$README_NAME"
    note "wrote $MIRROR/$README_NAME"
  fi

  if [ ! -e AGENTS.md ]; then
    stub_content >AGENTS.md
    note "created the root AGENTS.md stub (scaffolded once, never overwritten)"
  fi

  if [ "$changed" -eq 0 ]; then
    echo "docs-sync: nothing to do — $MIRROR/ already mirrors $origin exactly"
  else
    echo "docs-sync: $changed change(s); $MIRROR/ now mirrors $origin exactly"
  fi
}

case "$mode" in
  check) run_check ;;
  fix) run_fix ;;
esac
