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
      # A "+++ " line names the file only in the header, straight after the
      # "--- " line. Inside a hunk it is an added line whose text starts
      # with "++ ".
      /^diff --git / { in_hunk = 0; after_minus = 0; next }
      !in_hunk && /^--- / { after_minus = 1; next }
      !in_hunk && after_minus && /^\+\+\+ / {
        file = substr($0, 5)
        sub(/^b\//, "", file)
        after_minus = 0
        next
      }
      /^@@ / {
        in_hunk = 1
        after_minus = 0
        match($0, /\+[0-9]+/)
        line = substr($0, RSTART + 1, RLENGTH - 1)
        next
      }
      in_hunk && /^\+/ { print file "\t" line "\t" substr($0, 2); line++ }
    '
}

# Collect the lines first, so that a git failure (for example, an unknown
# base ref) fails the script instead of reporting no exclusions.
lines="$(added_lines)"

generated_re='@Generated([^[:alnum:]_]|$)'
generated_dir_re='(^|/)[Gg]enerated/'
build_file_re='(^|/)(pom\.xml|build\.gradle(\.kts)?)$'
excludes_re='<[Ee]xcludes?>|[Ee]xcludes?[[:space:]]*[(=+]'

hits=0
while IFS=$'\t' read -r file line text; do
  [ -n "$file" ] || continue
  reason=""
  if [[ $text =~ $markers ]]; then
    reason="coverage exclusion"
  elif [[ $text =~ $generated_re ]] && ! [[ $file =~ $generated_dir_re ]]; then
    reason="@Generated outside generated code"
  elif [[ $file =~ $build_file_re ]] && [[ $text =~ $excludes_re ]] &&
    [ -f "$file" ] && grep -qi jacoco "$file"; then
    reason="JaCoCo exclusion"
  fi

  if [ -n "$reason" ]; then
    printf '%s:%s: %s: %s\n' "$file" "$line" "$reason" "$text"
    hits=$((hits + 1))
  fi
done <<<"$lines"

if [ "$hits" -gt 0 ]; then
  echo "Found $hits coverage exclusion(s) added since ${base_ref}. Add tests instead of excluding code." >&2
  exit 1
fi
echo "No coverage exclusions added since ${base_ref}."
