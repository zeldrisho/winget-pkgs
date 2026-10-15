#!/usr/bin/env bash
# Reads one JSON object per autoupdate check on stdin (produced by
# autoupdate-checks.yq) and writes the batched job matrix to $GITHUB_OUTPUT.
set -euo pipefail

matrix=$(jq -s -c '
  group_by(.identifier)
  | [range(0; length; 3) as $start
      | .[$start:$start + 3] as $packageGroups
      | ($packageGroups | flatten) as $checks
      | {
          name: ($packageGroups | map(.[0].identifier) | join(", ")),
          needsMsi: ($checks | any(.[]; .versionSource == "msi")),
          packages: $checks
        }
    ]')

echo "matrix=$matrix" >> "$GITHUB_OUTPUT"
