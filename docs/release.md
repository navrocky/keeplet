# Release

## Versioning
SemVer tags `X.Y.Z`, no `v` prefix. `scripts/build.sh` stamps the version into `metadata.json` from `git describe`.

A release is an annotated `x.y.z` tag on `main` whose message is the version followed by that
release's changelog bullets. Pushing it runs `release.yml`, which builds the widget and publishes
`keeplet-x.y.z.plasmoid` and `SHA256SUMS` on the GitHub release, with the tag's message (minus the
version line) as its release notes.

## CI (GitHub Actions)
- `.github/workflows/ci.yml` — on push to `main` and PRs: `scripts/build.sh`, uploads `dist/` as artifact `keeplet-plasmoid`.
- `.github/workflows/release.yml` — on an `x.y.z` tag: `scripts/build.sh`, creates the GitHub Release
  (or reuses one made in the GitHub UI) with `keeplet-x.y.z.plasmoid` and `SHA256SUMS`. A build
  whose version isn't exactly the tag (`0.1.0-3-gabc1234`) fails instead of being published.

Both call the same `scripts/build.sh`, so local and CI artifacts are built identically.

Repository secrets `GA_MEASUREMENT_ID` and `GA_API_SECRET` compile in the usage statistics keys
([analytics.md](analytics.md)) of release builds; CI test builds, forks and local builds have statistics off.

## Changelog
`CHANGELOG.md` is seeded from git by `scripts/update-changelog.sh`: it inserts a `# X.X.X (<date>)`
heading on top with one `- ` bullet per commit subject since the last version in the file (the whole
history on the first run). `X.X.X` is replaced with the real version when releasing.

### Tidying up the changelog
Edit only the section for commits since the last tagged release (`git tag -l`) — typically the
topmost, still-unreleased `# X.X.X` heading. The readers are people using the widget. For each entry:

- Drop entries of no interest to them: `README`/`AGENTS.md`/docs touch-ups, tests, CI and build
  tooling, spikes, typo fixes, reverted or rolled-back intermediate steps, and anything else that
  doesn't change what the widget does or looks like.
- Refactors and reorganizations (MVVM moves, renamed ViewModels, split modules, a new provider layer)
  are not interesting on their own — drop them, unless they visibly change the widget's look or
  behavior; then describe that change instead.
- Rephrase entries that describe an implementation step (a QML id, a ViewModel or file name, a
  binding detail like `accountsVm: accountsVm`) into a plain description of the user-visible result.
- Consolidate a run of incremental commits that build up one feature into a single bullet
  describing the feature's end state.
- Multiple commits touching the same area (sign-in, labels, the editor, link previews, settings,
  the panel icon) collapse into one bullet naming that area once.
- Keep bug fixes, new features and new install/release options — these are what users read the
  changelog for. Still aim to leave only what matters most: fold minor entries (small visual polish)
  into a closely related bullet.

Preserve the formatting: one heading per release (`# <x.y.z> (<date>)`, `# X.X.X (<date>)` while
unreleased), one `- ` bullet per entry, in English. Do not touch already-released sections.

Order entries in three groups: new features, then changes to existing behavior, then bug fixes
(`Fix …`). Within a group, keep the original newest-first order.

## Making a release
1. Start from an up-to-date `main` with fresh tags, clean tree:
   `git checkout main && git pull && git fetch --tags --force origin`
   (a tag may have been moved or created on GitHub).
2. Run `scripts/update-changelog.sh`.
3. Tidy up the new section (see above).
4. Pick the version: only bug fixes → patch (`0.1.0` → `0.1.1`); anything new → minor
   (`0.1.0` → `0.2.0`). Replace `X.X.X` in the heading with it.
   **Stop here**: show the user the tidied section with the version and wait for their approval —
   they may reword, drop or merge entries. Don't commit, tag or push before that.
5. Commit the changelog, tag that commit and push both:

   ```bash
   git commit -am "Release <x.y.z>"
   git tag -a <x.y.z> -F <message-file>   # "<x.y.z>", blank line, the section's bullets
   git push origin main <x.y.z>
   ```

6. Watch the `Release` run (`gh run watch`), then publish the `.plasmoid` from the GitHub release on
   the KDE Store (below).

Before a release that touches sync or sign-in, go through the manual end-to-end checklist in
[development.md](development.md).

A hotfix is the same flow with the next patch version: fix on `main`, then steps 1–6.

## KDE Store
store.kde.org runs on Pling (OCS API). Steps:
1. First release: create the product manually (category *Plasma 6 Extensions → Plasma Widgets*),
   upload the `.plasmoid` from the GitHub Release.
2. Automation: to be researched after the first release — whether Pling/OCS allows uploading
   new files with an API token (`secrets.KDE_STORE_TOKEN`, product id in a repo variable).
   If there is no reliable API, publishing stays a manual step documented here.
