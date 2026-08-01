# Agent Instructions

## Repository Scope
- This is the WinGet package manifest repository; most package work is under `manifests/`.
- This fork is intentionally shallow/sparse/partial; do not expand to a full clone unless explicitly asked.
- Do not create new manifests unless the user explicitly asks; this fork is maintained for Komac-driven update PRs.

## Search Rules
- Never recursively scan all of `manifests/`.
- Limit manifest reads/searches to the exact package path, for example `manifests/n/NextDNS/NextDNS/CLI/`.
- Use `git ls-tree` or `git sparse-checkout add <path>` for missing paths instead of cloning the full repo.

## Commands
| Task | Command |
|------|---------|
| Show sparse paths | `git sparse-checkout list` |
| Add one package path | `git sparse-checkout add manifests/<letter>/<publisher>/<package>` |
| Inspect tracked path without materializing all files | `git ls-tree -r --name-only HEAD <path>` |
| Manual Komac update | `komac update Package.Identifier --version 1.2.3 --urls https://example.invalid/installer.exe --submit` |

## CI Autoupdate
- Maintain `.github/workflows/syncFork.yml` to sync this fork before updates run.
- Maintain `.github/workflows/updatePackages.yml` for scheduled Komac updates.
- Package config files are named `autoupdate.yaml` and live in package-scoped manifest directories.
- Use Homebrew for `komac` and mikefarah `yq`; run `eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"` before `brew`.
- Komac requires `secrets.KOMAC_TOKEN` as a classic GitHub token with `public_repo` scope for upstream PR submission.

## External References
| Need | File / URL |
|------|------------|
| Komac CLI | `https://github.com/russellbanks/Komac` |
| Ubuntu Homebrew path note | `https://github.com/actions/runner-images/blob/main/images/ubuntu/Ubuntu2604-Readme.md#homebrew-note` |
