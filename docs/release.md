# Release

## Versioning
SemVer tags `vX.Y.Z`. `scripts/build.sh` stamps the version into `metadata.json` from `git describe`.

## CI (GitHub Actions)
- `.github/workflows/ci.yml` — on push to `main` and PRs: `scripts/build.sh`, uploads `dist/` as artifact `keeplet-plasmoid`.
- `.github/workflows/release.yml` (planned) — on `v*` tag: `scripts/build.sh`, create a GitHub Release
  with `keeplet-X.Y.Z.plasmoid` and `SHA256SUMS`, then publish to KDE Store.

Both call the same `scripts/build.sh`, so local and CI artifacts are built identically.

## KDE Store
store.kde.org runs on Pling (OCS API). Steps:
1. First release: create the product manually (category *Plasma 6 Extensions → Plasma Widgets*),
   upload the `.plasmoid` from the GitHub Release.
2. Automation: to be researched after the first release — whether Pling/OCS allows uploading
   new files with an API token (`secrets.KDE_STORE_TOKEN`, product id in a repo variable).
   If there is no reliable API, publishing stays a manual step documented here.
