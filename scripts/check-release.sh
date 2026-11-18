#!/usr/bin/env bash
# Runs the release guards for a version tag:
#
# - the tag matches SmileID::VERSION in lib/usesmileid/version.rb
# - CHANGELOG.md has a dated "## [X.Y.Z] - YYYY-MM-DD" heading for it
# - the major version matches the PRs labelled `breaking` that the release
#   ships: if any PR labelled `breaking` was merged after the previous stable
#   tag, the major version must increase, and a major version needs at least
#   one such PR, except 0.x to 1.0.0
#
# Usage: GITHUB_REPOSITORY=owner/repo scripts/check-release.sh <tag> [<commit>]
#
# release.yml runs it on the pushed tag. Pull requests labelled `release` run
# it before the tag exists, passing the commit the tag will point to. A pushed
# tag can't be moved or reused, so in that case the tag must not exist yet.
#
# Reads version.rb and CHANGELOG.md from the working tree, so check out
# <commit> (or the tag) first. Needs Ruby, full history and tags, and `gh`
# logged in. Set GH to use another command in place of `gh` (the tests use a
# stub).

set -euo pipefail

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  echo "usage: $0 <tag> [<commit>]" >&2
  exit 2
fi
tag="$1"
commit="${2:-$1}"
gh_cmd="${GH:-gh}"
here="$(cd "$(dirname "$0")" && pwd)"
version="${tag#v}"
failed=0

if [ "$#" -eq 2 ] && git rev-parse --quiet --verify "refs/tags/$tag" >/dev/null; then
  echo "::error::Tag $tag already exists. Bump the version in lib/usesmileid/version.rb and CHANGELOG.md."
  failed=1
fi

gem_version="$(ruby -Ilib -e 'require "usesmileid/version"; puts SmileID::VERSION')"
if [ "$version" != "$gem_version" ]; then
  echo "::error::Tag $tag (version $version) does not match lib/usesmileid/version.rb (SmileID::VERSION = $gem_version)"
  failed=1
fi

if ! grep -qE "^## \[${version//./\\.}\] - [0-9]{4}-[0-9]{2}-[0-9]{2}" CHANGELOG.md; then
  echo "::error::CHANGELOG.md has no dated '## [$version] - YYYY-MM-DD' heading for tag $tag"
  failed=1
fi

previous=""
if git rev-parse --quiet --verify "${commit}^{commit}^" >/dev/null; then
  previous="$("$here/previous-release-tag.sh" "${commit}^")"
fi
if [ -z "$previous" ]; then
  echo "::notice::No stable release before $tag, so there is nothing to compare with."
else
  # A PR is in this release when its merge commit is reachable from the
  # release commit but not from the previous release tag. Read the list
  # first, so that a gh failure fails the script.
  candidates="$("$gh_cmd" pr list --repo "$GITHUB_REPOSITORY" --state merged --label breaking \
    --limit 1000 --json number,mergeCommit \
    --jq '.[] | "\(.number) \(.mergeCommit.oid // "")"')"
  breaking_prs=""
  while read -r number sha; do
    if [ -n "$sha" ] &&
      git merge-base --is-ancestor "$sha" "$commit" 2>/dev/null &&
      ! git merge-base --is-ancestor "$sha" "$previous" 2>/dev/null; then
      breaking_prs="$breaking_prs #$number"
    fi
  done <<<"$candidates"

  previous_major="${previous#v}"
  previous_major="${previous_major%%.*}"
  tag_major="${version%%.*}"
  echo "Previous release $previous; breaking PRs in $previous..$tag:${breaking_prs:- none}"

  if [ -n "$breaking_prs" ] && [ "$tag_major" -le "$previous_major" ]; then
    echo "::error::PRs labelled 'breaking' are in this release ($breaking_prs ), so $tag must be a major version."
    failed=1
  fi
  # 0.x to 1.0.0 marks a stable API, not a break, so it needs no breaking PR.
  if [ -z "$breaking_prs" ] && [ "$tag_major" -gt "$previous_major" ] &&
    ! { [ "$previous_major" -eq 0 ] && [ "$tag_major" -eq 1 ]; }; then
    echo "::error::$tag is a major version, but no PR labelled 'breaking' is in $previous..$tag."
    failed=1
  fi
fi

if [ "$failed" -ne 0 ]; then
  exit 1
fi
echo "$tag passes the release checks."
