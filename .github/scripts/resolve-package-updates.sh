#!/usr/bin/env bash
set -euo pipefail

user_agent='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome Safari'
results=$(mktemp -d)
trap 'rm -rf "$results"' EXIT

resolve_package() {
  local package=$1
  local result=$2
  local check_url guards identifier root_installer_properties url_template_values url_templates
  local version_regex version_source version_template version_template_values
  check_url=$(jq -r '.checkUrl' <<< "$package")
  guards=$(jq -c '.guards // []' <<< "$package")
  identifier=$(jq -r '.identifier' <<< "$package")
  root_installer_properties=$(jq -c '.rootInstallerProperties // []' <<< "$package")
  url_template_values=$(jq -c '.urlTemplateValues // {}' <<< "$package")
  url_templates=$(jq -c '.urlTemplates' <<< "$package")
  version_regex=$(jq -r '.versionRegex' <<< "$package")
  version_source=$(jq -r '.versionSource // ""' <<< "$package")
  version_template=$(jq -r '.versionTemplate // ""' <<< "$package")
  version_template_values=$(jq -c '.versionTemplateValues // {}' <<< "$package")

  local headers source effective_url installer match body version
  headers=$(mktemp)
  source=$(mktemp)
  effective_url=$(curl -sSLI -A "$user_agent" -o "$headers" -w '%{url_effective}' "$check_url")
  (cat "$headers"; printf '\n%s\n' "$effective_url") > "$source"

  # grep prints the whole match, so versionRegex must use \K or match only the value.
  if [[ $version_source == msi ]]; then
    installer=$(mktemp)
    curl -fsSL -A "$user_agent" -o "$installer" "$check_url"
    match=$(msiinfo export "$installer" Property | grep -oP -- "$version_regex" | head -1 || true)
  elif [[ $version_source == exe ]]; then
    installer=$(mktemp)
    curl -fsSL -A "$user_agent" -o "$installer" "$check_url"
    match=$(strings -el "$installer" \
      | awk 'NR > 1 { print previous "\t" $0 } { previous = $0 }' \
      | grep -oP -- "$version_regex" | head -1 || true)
  else
    match=$(grep -oP -- "$version_regex" "$source" | head -1 || true)
    if [[ -z $match ]] || jq -e 'length > 0' <<< "$url_template_values" >/dev/null; then
      body=$(mktemp)
      curl -fsSL -A "$user_agent" -o "$body" "$check_url"
      cat "$body" >> "$source"
      match=$(grep -oP -- "$version_regex" "$source" | head -1 || true)
    fi
  fi
  if [[ -z $match ]]; then
    echo "Could not resolve version for $identifier" >&2
    return 1
  fi

  local entry guard_name guard_regex match_guard_regex guard match_guard normalized_guard normalized_match_guard
  while read -r entry; do
    guard_name=$(base64 --decode <<< "$entry" | jq -r '.name // "unnamed"')
    guard_regex=$(base64 --decode <<< "$entry" | jq -r '.sourceRegex')
    match_guard_regex=$(base64 --decode <<< "$entry" | jq -r '.matchRegex')
    guard=$(grep -oP -- "$guard_regex" "$source" | head -1 || true)
    match_guard=$(grep -oP -- "$match_guard_regex" <<< "$match" | head -1 || true)
    normalized_guard=$(tr -cd '[:alnum:]' <<< "$guard" | tr '[:upper:]' '[:lower:]')
    normalized_match_guard=$(tr -cd '[:alnum:]' <<< "$match_guard" | tr '[:upper:]' '[:lower:]')
    if [[ -z $guard || -z $match_guard || $normalized_guard != "$normalized_match_guard" ]]; then
      echo "Guard '$guard_name' mismatch for $identifier: source='$guard', match='$match_guard'" >&2
      return 1
    fi
  done < <(jq -r '.[] | @base64' <<< "$guards")

  if [[ -n $version_template ]]; then
    version=${version_template//\{MATCH\}/$match}
    local version_placeholder version_value_regex version_value
    while read -r entry; do
      version_placeholder=$(base64 --decode <<< "$entry" | jq -r '.key')
      version_value_regex=$(base64 --decode <<< "$entry" | jq -r '.value')
      version_value=$(grep -oP -- "$version_value_regex" <<< "$match" | head -1 || true)
      if [[ -z $version_value ]]; then
        echo "Could not resolve version placeholder {$version_placeholder} for $identifier" >&2
        return 1
      fi
      version=${version//\{$version_placeholder\}/$version_value}
    done < <(jq -r 'to_entries[] | @base64' <<< "$version_template_values")
  else
    version=$match
  fi

  local identifier_path first_letter manifest_path existing_versions
  identifier_path=${identifier//./\/}
  first_letter=$(printf '%s' "$identifier" | cut -c1 | tr '[:upper:]' '[:lower:]')
  manifest_path="manifests/$first_letter/$identifier_path"
  existing_versions=$(gh api "repos/microsoft/winget-pkgs/contents/$manifest_path" --jq '.[].name')
  if grep -Fxq "$version" <<< "$existing_versions"; then
    echo "$identifier $version already exists; skipping"
    printf 'null\n' > "$result"
    return
  fi

  local urls_json placeholder regex value
  urls_json=$(jq -c --arg version "$version" --arg match "$match" \
    'map(split("{VERSION}") | join($version) | split("{MATCH}") | join($match))' <<< "$url_templates")
  while read -r entry; do
    placeholder=$(base64 --decode <<< "$entry" | jq -r '.key')
    regex=$(base64 --decode <<< "$entry" | jq -r '.value')
    value=$(grep -oP -- "$regex" "$source" | head -1 || true)
    if [[ -z $value ]]; then
      echo "Could not resolve URL placeholder {$placeholder} for $identifier" >&2
      return 1
    fi
    urls_json=$(jq -c --arg placeholder "{$placeholder}" --arg value "$value" \
      'map(split($placeholder) | join($value))' <<< "$urls_json")
  done < <(jq -r 'to_entries[] | @base64' <<< "$url_template_values")

  jq -cn --arg identifier "$identifier" --arg version "$version" \
    --argjson rootInstallerProperties "$root_installer_properties" --argjson urls "$urls_json" \
    '{identifier: $identifier, version: $version, urls: $urls, rootInstallerProperties: $rootInstallerProperties}' > "$result"
}

pids=()
index=0
while read -r package; do
  resolve_package "$package" "$results/$index.json" &
  pids+=("$!")
  index=$((index + 1))
done < <(jq -c '.[]' <<< "$PACKAGES_JSON")

failed=0
for pid in "${pids[@]}"; do
  if ! wait "$pid"; then
    failed=1
  fi
done
[[ $failed -eq 0 ]] || exit 1

updates=$(jq -s -c '
  map(select(. != null))
  | group_by([.identifier, .version])
  | map({
      identifier: .[0].identifier,
      version: .[0].version,
      urls: (map(.urls[]) | unique),
      rootInstallerProperties: (map(.rootInstallerProperties[]) | unique)
    })
' "$results"/*.json)
echo "updates=$updates" >> "$GITHUB_OUTPUT"
