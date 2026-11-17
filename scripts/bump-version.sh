#!/usr/bin/env bash
# Bumps the gem version and moves the changelog's Unreleased notes under a
# heading for the new version.
#
# Usage: scripts/bump-version.sh <major|minor|patch>
#
# Updates SmileID::VERSION in lib/usesmileid/version.rb (release.yml checks the
# tag against it) and CHANGELOG.md, then prints the new version. Fails without
# changing anything if CHANGELOG.md has nothing under Unreleased, or if either
# file is not in the expected shape.
#
# BUMP_VERSION_ROOT and BUMP_VERSION_DATE override the repository root and the
# release date (YYYY-MM-DD, default today in UTC). The tests use them.
set -euo pipefail

fail() {
  echo "bump-version: $*" >&2
  exit 1
}

[ "$#" -eq 1 ] || fail "usage: $0 <major|minor|patch>"
part="$1"

root="${BUMP_VERSION_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
version_file="$root/lib/usesmileid/version.rb"
changelog="$root/CHANGELOG.md"
release_date="${BUMP_VERSION_DATE:-$(date -u +%Y-%m-%d)}"
version_line="^  VERSION = '[0-9]+\.[0-9]+\.[0-9]+'$"

[ -f "$version_file" ] || fail "$version_file not found"
[ -f "$changelog" ] || fail "$changelog not found"
[ "$({ grep -Ec "$version_line" "$version_file" || true; })" -eq 1 ] ||
  fail "$version_file must have exactly one line like: VERSION = '1.2.3'"
[ "$({ grep -c '^## \[Unreleased\]$' "$changelog" || true; })" -eq 1 ] ||
  fail "$changelog must have exactly one '## [Unreleased]' heading"

current="$(grep -E "$version_line" "$version_file" | sed -E "s/.*'(.*)'.*/\1/")"
IFS=. read -r major minor patch <<EOF
$current
EOF

case "$part" in
  major) next="$((major + 1)).0.0" ;;
  minor) next="${major}.$((minor + 1)).0" ;;
  patch) next="${major}.${minor}.$((patch + 1))" ;;
  *) fail "unknown part '$part'; use major, minor or patch" ;;
esac

if grep -q "^## \[${next//./\\.}\]" "$changelog"; then
  fail "$changelog already has a '## [$next]' heading"
fi

# Text between '## [Unreleased]' and the next '## ' heading, ignoring blank lines.
unreleased="$(awk '/^## \[Unreleased\]$/ { inside = 1; next } inside && /^## / { exit } inside && NF { print }' "$changelog")"
[ -n "$unreleased" ] || fail "nothing to release: the Unreleased section of $changelog is empty"

tmp_changelog="$(mktemp)"
tmp_version="$(mktemp)"
trap 'rm -f "$tmp_changelog" "$tmp_version"' EXIT

# Add the new heading under Unreleased, and update the compare links at the
# bottom when the changelog has them.
awk -v next_version="$next" -v current="$current" -v date="$release_date" '
  $0 == "## [Unreleased]" {
    print
    print ""
    print "## [" next_version "] - " date
    next
  }
  /^\[Unreleased\]: .*\/compare\/v[0-9.]+\.\.\.HEAD$/ {
    base = $0
    sub(/\/compare\/.*/, "", base)
    sub(/^\[Unreleased\]: /, "", base)
    print "[Unreleased]: " base "/compare/v" next_version "...HEAD"
    print "[" next_version "]: " base "/compare/v" current "...v" next_version
    next
  }
  { print }
' "$changelog" >"$tmp_changelog"

sed -E "s/^  VERSION = '[0-9.]+'$/  VERSION = '${next}'/" "$version_file" >"$tmp_version"

cat "$tmp_changelog" >"$changelog"
cat "$tmp_version" >"$version_file"

echo "$next"
