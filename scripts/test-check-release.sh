#!/usr/bin/env bash
# Tests scripts/check-release.sh in a throwaway git repository, with a stub in
# place of `gh`.
#
# Usage: scripts/test-check-release.sh

set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failures=0

fail() {
  echo "FAIL: $*" >&2
  failures=$((failures + 1))
}

export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
export GIT_CONFIG_NOSYSTEM=1 HOME="$work"
export GITHUB_REPOSITORY=o/r

# A stub `gh pr list ... --jq ...` that prints the recorded breaking PRs as
# "<number> <merge commit sha>" lines.
: >"$work/breaking"
cat >"$work/gh" <<EOF
#!/usr/bin/env bash
cat "$work/breaking"
EOF
chmod +x "$work/gh"
export GH="$work/gh"

repo="$work/repo"
git init -q -b main "$repo"
mkdir -p "$repo/scripts" "$repo/lib/usesmileid"
cp "$here/previous-release-tag.sh" "$here/check-release.sh" "$repo/scripts/"
cd "$repo"

# release <version> <changelog heading>: commits a version bump.
release() {
  printf "module SmileID\n  VERSION = '%s'\nend\n" "$1" >lib/usesmileid/version.rb
  printf '# Changelog\n\n## [Unreleased]\n\n%s\n' "$2" >CHANGELOG.md
  git add -A && git commit -q -m "release $1"
}

expect() {
  local want="$1" rc=0
  shift
  scripts/check-release.sh "$@" >"$work/out" 2>&1 || rc=$?
  if [ "$want" = pass ] && [ "$rc" -ne 0 ]; then
    fail "check-release $*: expected pass"
    cat "$work/out" >&2
  elif [ "$want" = fail ] && [ "$rc" -eq 0 ]; then
    fail "check-release $*: expected failure"
    cat "$work/out" >&2
  fi
}

release 0.9.0 '## [0.9.0] - 2026-01-01'
git tag v0.9.0
expect pass v0.9.0 # first release, nothing to compare with
expect fail v0.9.1 # version.rb says 0.9.0

release 1.0.0 '## [1.0.0] - 2026-01-02'
expect pass v1.0.0 HEAD # 0.x to 1.0.0 needs no breaking PR
git tag v1.0.0
expect pass v1.0.0
expect fail v1.0.0 HEAD # a pull request can't release a tagged version

release 1.1.0 '## [1.1.0]'
expect fail v1.1.0 HEAD # the heading has no date

git commit -q --allow-empty -m 'breaking change'
echo "7 $(git rev-parse HEAD)" >>"$work/breaking"
echo "8 " >>"$work/breaking" # an unmerged PR has no merge commit
release 1.1.0 '## [1.1.0] - 2026-01-03'
expect fail v1.1.0 HEAD # ships #7 without a major bump
release 2.0.0 '## [2.0.0] - 2026-01-03'
expect pass v2.0.0 HEAD
git tag v2.0.0

release 3.0.0 '## [3.0.0] - 2026-01-04'
expect fail v3.0.0 HEAD # a major bump with no breaking PR since v2.0.0
release 2.1.0 '## [2.1.0] - 2026-01-04'
expect pass v2.1.0 HEAD # #7 shipped in v2.0.0

if [ "$failures" -ne 0 ]; then
  echo "$failures check-release test(s) failed" >&2
  exit 1
fi
echo "check-release tests passed"
