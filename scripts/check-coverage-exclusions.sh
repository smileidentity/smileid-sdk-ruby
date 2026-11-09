#!/usr/bin/env bash
# Fails if the lines added since <base-ref> exclude code from coverage.
#
# Usage: scripts/check-coverage-exclusions.sh <base-ref>
#
# Scans the added lines of `git diff <base-ref>...HEAD` for coverage exclusion
# markers used across the Smile ID SDKs: nocov, pragma: no cover, c8 ignore,
# istanbul ignore, @codeCoverageIgnore, #[coverage(off)], @Generated outside
# generated code, and new excludes in a JaCoCo config. Prints each hit as
# file:line: text and exits 1 if there are any.
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <base-ref>" >&2
  exit 2
fi
base_ref="$1"

markers='nocov|pragma: no cover|c8 ignore|istanbul ignore|@codeCoverageIgnore|#\[coverage\(off\)\]'

# This script and its spec name every marker, so they are left out of the scan.
added_lines() {
  git diff --unified=0 --no-color --no-ext-diff "${base_ref}...HEAD" -- . \
    ':(exclude)scripts/check-coverage-exclusions.sh' \
    ':(exclude)spec/scripts/check_coverage_exclusions_spec.rb' |
    awk '
      /^\+\+\+ / { file = substr($0, 7); next }
      /^@@ / {
        match($0, /\+[0-9]+/)
        line = substr($0, RSTART + 1, RLENGTH - 1)
        next
      }
      /^\+/ { print file "\t" line "\t" substr($0, 2); line++ }
    '
}

hits=0
while IFS=$'\t' read -r file line text; do
  reason=""
  if printf '%s\n' "$text" | grep -Eq "$markers"; then
    reason="coverage exclusion"
  elif printf '%s\n' "$text" | grep -Eq '@Generated\b' && ! printf '%s\n' "$file" | grep -Eqi '(^|/)generated/'; then
    reason="@Generated outside generated code"
  elif printf '%s\n' "$file" | grep -Eq '(^|/)(pom\.xml|build\.gradle(\.kts)?)$' &&
    printf '%s\n' "$text" | grep -Eqi '<excludes?>|excludes?[[:space:]]*[(=+]' &&
    [ -f "$file" ] && grep -qi jacoco "$file"; then
    reason="JaCoCo exclusion"
  fi

  if [ -n "$reason" ]; then
    printf '%s:%s: %s: %s\n' "$file" "$line" "$reason" "$text"
    hits=$((hits + 1))
  fi
done < <(added_lines)

if [ "$hits" -gt 0 ]; then
  echo "Found $hits coverage exclusion(s) added since ${base_ref}. Add tests instead of excluding code." >&2
  exit 1
fi
echo "No coverage exclusions added since ${base_ref}."
