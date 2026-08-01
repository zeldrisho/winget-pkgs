#!/usr/bin/env bash
set -euo pipefail

if [[ ! -d manifests ]]; then
  echo 'matrix=[]' >> "$GITHUB_OUTPUT"
  exit 0
fi

matrix=$(find manifests -name autoupdate.yaml -print | sort | while read -r file; do
  directory=$(dirname "$file")
  relative=${directory#manifests/*/}
  identifier=${relative//\//.}
  yq -o=json '.' "$file" | jq -c --arg identifier "$identifier" '
    if has("checks") then
      .checks[] + {identifier: $identifier}
    else
      . + {identifier: $identifier}
    end
  '
done | jq -s -c '
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
