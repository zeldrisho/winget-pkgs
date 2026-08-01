# Agent Instructions

## Scope
- This is a shallow, sparse fork of the WinGet manifest repository.
- Do not expand it to a full clone or recursively scan `manifests/`.
- Do not create version manifests unless explicitly asked; updates are submitted by Komac CI.

## Autoupdate Packages
- Convert an identifier to `manifests/<lowercase-first-letter>/<identifier-with-dots-as-slashes>/`.
- Inspect paths with `git ls-tree`; materialize only the latest stable `*.installer.yaml` and package-level `autoupdate.yaml` using non-cone sparse checkout.
- Do not materialize version or locale manifests; inspect multiple installer manifests only when explicitly requested.
- Treat supplied examples only as checkver references.
- Read the complete latest stable `*.installer.yaml` as the source of truth for version format, installer URLs, architectures, types, and installer count.
- Verify the check URL, regex, resolved version, and every generated installer URL locally.
- Configure `checkUrl`, `versionRegex`, and list-valued `urlTemplates` in `autoupdate.yaml`.
- Use `{VERSION}` for the submitted package version and `{MATCH}` for the raw regex result.
- Use `versionTemplate` when WinGet's version differs from the raw check result; derive variable components instead of hardcoding them.
- Use `versionTemplateValues` for regex-derived version placeholders.
- Use `urlTemplateValues` for additional regex-derived URL placeholders.
- Use `guards` with independent source/match regexes when historical matches can outlive the latest release.
- Use `versionSource: msi` when the version comes from the MSI `ProductVersion`.
- Keep publisher-replaced installer URLs unchanged; do not copy hashes into the config.
- Use `rootInstallerProperties` when WinGet requires first-installer values to retain root-level inheritance.

## CI and Tools
- `.github/workflows/syncFork.yml` syncs upstream; a successful run triggers `.github/workflows/updatePackages.yml`.
- Keep updater logic in `.github/scripts/`; preserve identifier grouping, three-package batches, and concurrent checks.
- CI uses `Homebrew/actions/setup-homebrew` and Brew-installed `komac` and mikefarah `yq`.
- CI installs `msitools` with APT only for MSI version checks.
- Locally use `actionlint` for workflows, `yq` for matrix generation, APT-installed `msitools` for MSI checks, and Komac `analyze`/`update --dry-run` for generated-manifest checks.
- Pass `--token "$(gh auth token)"` to local Komac commands because headless Linux lacks Secret Service storage.
- Fork sync uses the workflow's `GITHUB_TOKEN` with `contents: write`.
- Komac submission and cleanup use `secrets.KOMAC_TOKEN`, a classic token with `public_repo` scope.
- Fix generated Komac PRs by amending their existing commit and pushing with `--force-with-lease`; do not add follow-up commits.

## References
- Komac: `https://github.com/russellbanks/Komac`
- Homebrew setup: `https://github.com/Homebrew/actions/tree/HEAD/setup-homebrew`
