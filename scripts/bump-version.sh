#!/usr/bin/env bash
# Bumps the gem version and moves the changelog's Unreleased notes under a
# heading for the new version.
#
# Usage: scripts/bump-version.sh <major|minor|patch|X.Y.Z>
#
# Pass a part to bump, or an exact X.Y.Z (plain digits, no leading zeros) that
# is greater than the current version. All SDKs release at one shared version,
# so an SDK that skipped a release jumps straight to it.
#
# Updates SmileID::VERSION in lib/usesmileid/version.rb (release.yml checks the
# tag against it), CHANGELOG.md, the gem's own entry in Gemfile.lock and the
# pinned version in spec/usesmileid/version_spec.rb (each when present), then
# prints the new version. Fails without changing anything if CHANGELOG.md has
# nothing under Unreleased, or if any file is not in the expected shape.
#
# BUMP_VERSION_ROOT and BUMP_VERSION_DATE override the repository root and the
# release date (YYYY-MM-DD, default today in UTC). The tests use them.
set -euo pipefail

fail() {
  echo "bump-version: $*" >&2
  exit 1
}

[ "$#" -eq 1 ] || fail "usage: $0 <major|minor|patch|X.Y.Z>"
part="$1"

root="${BUMP_VERSION_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
version_file="$root/lib/usesmileid/version.rb"
changelog="$root/CHANGELOG.md"
lockfile="$root/Gemfile.lock"
version_spec="$root/spec/usesmileid/version_spec.rb"
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

semver='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'

case "$part" in
  major) next="$((major + 1)).0.0" ;;
  minor) next="${major}.$((minor + 1)).0" ;;
  patch) next="${major}.${minor}.$((patch + 1))" ;;
  [0-9]*)
    # [[ =~ ]] matches the whole argument; grep would pass one with a newline in it.
    [[ "$part" =~ $semver ]] ||
      fail "invalid version '$part'; use X.Y.Z with plain digits, like 1.2.3"
    IFS=. read -r next_major next_minor next_patch <<EOF
$part
EOF
    if [ "$next_major" -gt "$major" ] ||
      { [ "$next_major" -eq "$major" ] && [ "$next_minor" -gt "$minor" ]; } ||
      { [ "$next_major" -eq "$major" ] && [ "$next_minor" -eq "$minor" ] && [ "$next_patch" -gt "$patch" ]; }; then
      next="$part"
    else
      fail "version $part must be greater than the current version $current"
    fi
    ;;
  *) fail "unknown part '$part'; use major, minor, patch or X.Y.Z" ;;
esac

current_re="${current//./\\.}"
lock_line="^    usesmileid \\(${current_re}\\)$"
spec_line="^    expect\\(SmileID::VERSION\\)\\.to eq\\('[0-9]+\\.[0-9]+\\.[0-9]+'\\)$"

if [ -f "$lockfile" ]; then
  [ "$({ grep -Ec "$lock_line" "$lockfile" || true; })" -eq 1 ] ||
    fail "$lockfile must have exactly one line like: usesmileid ($current)"
fi
if [ -f "$version_spec" ]; then
  spec_pins="$({ grep -Ec "$spec_line" "$version_spec" || true; })"
  [ "$spec_pins" -le 1 ] || fail "$version_spec pins the version more than once"
  if [ "$spec_pins" -eq 1 ]; then
    grep -Eq "^    expect\\(SmileID::VERSION\\)\\.to eq\\('${current_re}'\\)$" "$version_spec" ||
      fail "$version_spec pins a version other than the current $current"
  fi
fi

if grep -q "^## \[${next//./\\.}\]" "$changelog"; then
  fail "$changelog already has a '## [$next]' heading"
fi

# Text between '## [Unreleased]' and the next '## ' heading, ignoring blank lines.
unreleased="$(awk '/^## \[Unreleased\]$/ { inside = 1; next } inside && /^## / { exit } inside && NF { print }' "$changelog")"
[ -n "$unreleased" ] || fail "nothing to release: the Unreleased section of $changelog is empty"

tmp_changelog="$(mktemp)"
tmp_version="$(mktemp)"
tmp_lockfile="$(mktemp)"
tmp_spec="$(mktemp)"
trap 'rm -f "$tmp_changelog" "$tmp_version" "$tmp_lockfile" "$tmp_spec"' EXIT

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
if [ -f "$lockfile" ]; then
  sed -E "s/${lock_line}/    usesmileid (${next})/" "$lockfile" >"$tmp_lockfile"
fi
if [ -f "$version_spec" ]; then
  sed -E "s/${spec_line}/    expect(SmileID::VERSION).to eq('${next}')/" "$version_spec" >"$tmp_spec"
fi

# Write only once every new file is ready, so a failure changes nothing.
cat "$tmp_changelog" >"$changelog"
cat "$tmp_version" >"$version_file"
[ ! -f "$lockfile" ] || cat "$tmp_lockfile" >"$lockfile"
[ ! -f "$version_spec" ] || cat "$tmp_spec" >"$version_spec"

echo "$next"
