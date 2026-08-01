#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repository_root=$(git -C "$script_dir" rev-parse --show-toplevel)

find_pr_number() {
  local identifier=$1
  local version=$2
  local komac_log=$3
  local pr_number query
  pr_number=$(grep -oP 'github\.com/microsoft/winget-pkgs/pull/\K\d+' "$komac_log" | tail -1 || true)

  if [[ -z $pr_number ]]; then
    query="repo:microsoft/winget-pkgs is:pr is:open author:$FORK_OWNER in:title \"New version: $identifier version $version\""
    for _ in {1..6}; do
      pr_number=$(gh api --method GET search/issues -f q="$query" --jq '.items[0].number // empty')
      [[ -n $pr_number ]] && break
      sleep 10
    done
  fi

  if [[ -z $pr_number ]]; then
    echo "Could not find the Komac PR for $identifier $version" >&2
    return 1
  fi
  printf '%s\n' "$pr_number"
}

amend_root_installer_properties() {
  local identifier=$1
  local version=$2
  local properties=$3
  local komac_log=$4
  local pr_number head_owner head_ref
  pr_number=$(find_pr_number "$identifier" "$version" "$komac_log")
  head_owner=$(gh api "repos/microsoft/winget-pkgs/pulls/$pr_number" --jq '.head.repo.owner.login')
  head_ref=$(gh api "repos/microsoft/winget-pkgs/pulls/$pr_number" --jq '.head.ref')
  if [[ ${head_owner,,} != "${FORK_OWNER,,}" ]]; then
    echo "Refusing to amend PR #$pr_number owned by $head_owner" >&2
    return 1
  fi

  local identifier_path manifest_path worktree
  identifier_path=${identifier//./\/}
  manifest_path="manifests/$(cut -c1 <<< "$identifier" | tr '[:upper:]' '[:lower:]')/$identifier_path/$version/$identifier.installer.yaml"
  worktree=$(mktemp -d)
  rmdir "$worktree"
  git -C "$repository_root" fetch --no-tags --filter=blob:none origin \
    "+refs/heads/$head_ref:refs/remotes/origin/$head_ref"
  git -C "$repository_root" worktree add --no-checkout "$worktree" \
    "refs/remotes/origin/$head_ref"
  printf '%s\n' '/*' '!/*/' "/$manifest_path" \
    | git -C "$worktree" sparse-checkout set --no-cone --stdin
  git -C "$worktree" checkout

  python3 "$script_dir/promote-root-installer-properties.py" \
    "$worktree/$manifest_path" "$properties"
  git -C "$worktree" diff --check
  if ! git -C "$worktree" diff --quiet; then
    git -C "$worktree" config user.name github-actions[bot]
    git -C "$worktree" config user.email 41898282+github-actions[bot]@users.noreply.github.com
    git -C "$worktree" add "$manifest_path"
    git -C "$worktree" commit --amend --no-edit
    gh auth setup-git
    git -C "$worktree" push --force-with-lease origin "HEAD:$head_ref"
  fi
  git -C "$repository_root" worktree remove --force "$worktree"
}

while read -r update; do
  identifier=$(jq -r '.identifier' <<< "$update")
  version=$(jq -r '.version' <<< "$update")
  properties=$(jq -c '.rootInstallerProperties' <<< "$update")
  readarray -t urls < <(jq -r '.urls[]' <<< "$update")
  komac_log=$(mktemp)

  for attempt in {1..3}; do
    set +e
    komac update "$identifier" \
      --version "$version" \
      --urls "${urls[@]}" \
      --token "$KOMAC_TOKEN" \
      --submit 2>&1 | tee "$komac_log"
    status=${PIPESTATUS[0]}
    set -e
    [[ $status -eq 0 ]] && break
    if [[ $attempt -eq 3 ]] || ! grep -Fq 'Ref cannot be created.' "$komac_log"; then
      exit "$status"
    fi
    echo "Komac could not create the branch; retrying ($attempt/3)" >&2
    sleep 5
  done

  if jq -e 'length > 0' <<< "$properties" >/dev/null; then
    amend_root_installer_properties "$identifier" "$version" "$properties" "$komac_log"
  fi
done < <(jq -c '.[]' <<< "$UPDATES_JSON")
