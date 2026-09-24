#!/usr/bin/env bash
# lib/track.sh — release tracks (#618): one repository, several version lines.
#
# A track is a directory holding its own version source (VERSION or
# package.json), CHANGELOG.md, changelog.d/ and drills/, released under its
# own tag prefix. The default track — path ".", prefix "" — is every
# repository that existed before tracks, byte for byte: every helper here is
# the identity on it, so a caller that never names a track sees no change.
#
# Paths stay relative to the repository root, never cd'd into: the guards
# read `git show <rev>:<path>`, whose right-hand side is root-relative, so a
# working-directory switch would read the wrong file silently. Prefixing
# keeps one frame of reference for git and for the filesystem alike.
#
# Sourced, not executed. Functions print on stdout and diagnose on stderr.

# track_path_normalize <path> — print the canonical form of a track path, or
# refuse. "" and "." are the default track; "./apps/admin/" becomes
# "apps/admin". Absolute paths and ".." segments are refused: a track lives
# inside the repository, and the re-arm commits under it.
track_path_normalize() {
  local path="${1-}"
  case "$path" in
    '' | . | ./) printf '.\n'; return 0 ;;
    /*)
      echo "track: path '$path' is absolute — a track is a directory inside the repository, relative to its root" >&2
      return 1
      ;;
  esac
  while [ "${path#./}" != "$path" ]; do path="${path#./}"; done
  while [ "${path%/}" != "$path" ]; do path="${path%/}"; done
  case "/$path/" in
    */../* | */./*)
      echo "track: path '$1' has a '.' or '..' segment — name the track's directory directly, relative to the repository root" >&2
      return 1
      ;;
    *//*)
      echo "track: path '$1' has an empty segment" >&2
      return 1
      ;;
  esac
  printf '%s\n' "$path"
}

# track_file <path> <name> — the root-relative path of <name> inside the
# track. The default track returns <name> untouched, so messages and git
# pathspecs read exactly as they did before tracks existed.
track_file() {
  local path="${1:?track_file: path required}" name="${2:?track_file: name required}"
  if [ "$path" = . ]; then
    printf '%s\n' "$name"
  else
    printf '%s/%s\n' "$path" "$name"
  fi
}

# track_prefix_check <prefix> — refuse a prefix that cannot be a literal tag
# prefix. Empty is the default track. A prefix must start with a letter (so a
# bare version is never mistaken for one track's tag, nor one track's tag for
# a bare version) and holds only characters a tag and a release name carry
# without quoting — no glob characters, since the prefix is matched literally.
track_prefix_check() {
  local prefix="${1-}"
  [ -z "$prefix" ] && return 0
  if [[ ! "$prefix" =~ ^[A-Za-z][A-Za-z0-9._/-]*$ ]]; then
    echo "track: tag-prefix '$prefix' must start with a letter and hold only letters, digits, '.', '_', '/' or '-'" >&2
    return 1
  fi
}

# track_tag <prefix> <version> — the tag and release name for a version.
track_tag() {
  printf '%s%s\n' "${1-}" "${2:?track_tag: version required}"
}
