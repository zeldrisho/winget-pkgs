# Agent Instructions

## Toolchain

- Shallow, sparse fork of `microsoft/winget-pkgs`; never expand it to a full clone.
- CI: `actions/checkout`, `mikefarah/yq` (Docker, not on PATH), `UnownPlain/install-komac`; `msitools` via APT only for MSI checks.
- Local `yq` must be mikefarah v4; apt's `yq` is incompatible.
- Local Komac needs `--token "$(gh auth token)"`; headless Linux has no Secret Service.
- `secrets.KOMAC_TOKEN` is a classic token with `public_repo` scope.

## Commands

| Task                 | Command                                                                                                                                                                                         |
| -------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Lint workflows       | `actionlint .github/workflows/syncManifests.yml .github/workflows/updatePackages.yml`                                                                                                           |
| Lint scripts         | `shellcheck .github/scripts/*.sh`                                                                                                                                                               |
| Build update matrix  | `yq -o=json -I=0 --from-file .github/scripts/autoupdate-checks.yq $(git ls-files ':(glob)manifests/**/autoupdate.yaml') \| GITHUB_OUTPUT=/dev/stdout .github/scripts/generate-update-matrix.sh` |
| Resolve one package  | `PACKAGES_JSON='[<check + identifier>]' GH_TOKEN="$(gh auth token)" GITHUB_OUTPUT=/dev/stdout .github/scripts/resolve-package-updates.sh`                                                         |
| Dry-run a submission | `komac update <Identifier> --version <v> --urls <url>... --dry-run --token "$(gh auth token)"`                                                                                                  |

## Rules

- Do not create version manifests unless asked; Komac CI submits them.
- Never recursively scan `manifests/` or list full history; bound history queries by path and count.
- Prefer targeted checks and CI over worktrees, merges, or full validation; ask before costly reproduction.
- Keep updater logic in `.github/scripts/`; preserve identifier grouping, three-package batches, and concurrent checks.
- A failed check is skipped, not fatal: `resolve-package-updates.sh` sets `failed=1`, the rest of the batch still submits, and the workflow only warns.
- Pin every action to a commit hash with a version comment; no Homebrew in CI.
- `autoupdate.yaml` is fork-only, at `manifests/<lowercase-first-letter>/<Identifier with dots as slashes>/autoupdate.yaml`; `syncManifests.yml` never restores it.
- Inspect with `git ls-tree`; non-cone sparse-checkout only the latest stable `*.installer.yaml` and `autoupdate.yaml`.
- The latest stable installer manifest is the source of truth for version format, URLs, architectures, types, and installer count.
- Treat user-supplied examples only as checkver references.
- Verify the check URL, regex, resolved version, and every generated installer URL locally.
- Regexes run through `grep -oP`: first match wins; print only the value with `\K` or lookahead.
- Headers and the final URL are searched first; the body is fetched only if nothing matches or `urlTemplateValues` is set.
- Keep publisher-replaced installer URLs unchanged; never put hashes in the config.
- Fix generated Komac PRs by amending their commit and pushing with `--force-with-lease`; no follow-up commits.

| Key                                        | Use                                                                                                   |
| ------------------------------------------ | ----------------------------------------------------------------------------------------------------- |
| `checkUrl`, `versionRegex`                 | Where to look and how to match                                                                        |
| `urlTemplates`                             | One URL as a string, several as a list; `{VERSION}` is the submitted version, `{MATCH}` the raw match |
| `versionTemplate`, `versionTemplateValues` | WinGet version differs from the match; placeholder to regex, run on the match                         |
| `urlTemplateValues`                        | Placeholder to regex, run on the source, for extra URL parts                                          |
| `guards`                                   | `name`, `sourceRegex`, `matchRegex` must agree after case and punctuation are dropped                 |
| `versionSource: msi`                       | Version from MSI `ProductVersion`; regex runs on `msiinfo export <file> Property`                     |
| `rootInstallerProperties`                  | First-installer properties promoted to manifest root after submission                                 |
| `checks:`                                  | Independent version streams; see `manifests/u/UniKey/UniKey/autoupdate.yaml`                          |

## References

| Need               | File                                    |
| ------------------ | --------------------------------------- |
| Manifest authoring | `doc/Authoring.md`                      |
| Manifest schemas   | `schemas/JSON/`                         |
| Contributing       | `CONTRIBUTING.md`                       |
| Komac CLI          | `https://github.com/russellbanks/Komac` |
