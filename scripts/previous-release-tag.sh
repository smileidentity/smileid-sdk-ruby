#!/usr/bin/env bash
# Prints the newest stable release tag (vX.Y.Z, no pre-release suffix) that is
# an ancestor of <ref>, or nothing if there is none.
#
# Usage: scripts/previous-release-tag.sh <ref>
#
# Examples:
#   scripts/previous-release-tag.sh origin/main    # last release on main
#   scripts/previous-release-tag.sh "v12.2.0^"     # release before v12.2.0
#
# Only tags reachable from <ref> count, so a backport tag such as v11.4.1
# sees v11.4.0, not a v12 tag on another line.
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <ref>" >&2
  exit 2
fi

git tag --merged "$1" --list 'v*' --sort=-version:refname |
  awk '/^v[0-9]+\.[0-9]+\.[0-9]+$/ && !found { print; found = 1 }'
