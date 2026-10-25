# Release

## Versioning
SemVer tags `X.Y.Z`, no `v` prefix. `scripts/build.sh` stamps the version into `metadata.json` from `git describe`.

A release is an annotated `x.y.z` tag on `main` whose message is the version followed by that
release's changelog bullets. Pushing it runs `release.yml`, which builds the widget and publishes
`keeplet-x.y.z.plasmoid` and `SHA256SUMS` on the GitHub release, with the tag's message (minus the
version line) as its release notes, and then the same `.plasmoid` on the KDE Store.

## CI (GitHub Actions)
- `.github/workflows/ci.yml` — on push to `main` and PRs: `scripts/build.sh`, uploads `dist/` as artifact `keeplet-plasmoid`.
- `.github/workflows/release.yml` — on an `x.y.z` tag: `scripts/build.sh`, creates the GitHub Release
  (or reuses one made in the GitHub UI) with `keeplet-x.y.z.plasmoid` and `SHA256SUMS`. A build
  whose version isn't exactly the tag (`0.1.0-3-gabc1234`) fails instead of being published.
  Then uploads the same file to the KDE Store (below).

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

6. Watch the `Release` run (`gh run watch`), then check the version on the
   [store page](https://store.kde.org/p/2379427/).

Before a release that touches sync or sign-in, go through the manual end-to-end checklist in
[development.md](development.md).

A hotfix is the same flow with the next patch version: fix on `main`, then steps 1–6.

## KDE Store
The widget is product [2379427](https://store.kde.org/p/2379427/) on store.kde.org (Pling/opendesktop),
category *Plasma 6 Extensions → Plasma Widgets*. Plasma's *Get New Widgets…* lists published
products of that category that have a file, so the product must stay published.

Only a release publishes there: the last step of `release.yml` runs `scripts/kde-store-upload.sh`, which
uploads `keeplet-x.y.z.plasmoid` with its version, archives the older files, adds (or updates)
a changelog entry `x.y.z` with the tag's notes and sets the product's own *Version* field to `x.y.z`.
Don't upload releases by hand.

The product version is a field of the edit page's main form, which saves only as a whole: the script
sends the form back with its current values (title, description, license, tags, …) and only the
version changed, then reads the page again and fails if the version didn't stick or any other field
changed. It needs `python3` to read the form.

That field is what running widgets compare their version with: once it is set, users see the
"Keeplet x.y.z is out" notice within a day (see the update notes in [plasmoid.md](plasmoid.md)).

"Archived" means the file's *compatible* checkbox on the edit page is cleared: the store's OCS API,
which Get New Widgets reads, lists only compatible files, so Plasma offers just the latest version,
while the older ones stay downloadable on the store page. Nothing is deleted, and the new file is
uploaded before the old ones are archived, so the product always has a file.

- Pling has no write API (the OCS API is read-only), so the script signs in with e-mail and password —
  repository secrets `KDE_STORE_USERNAME` and `KDE_STORE_PASSWORD` — and calls the AJAX endpoints of
  the product's edit page. They are undocumented: if the store changes them the step fails; then
  fix the script (or, as a stopgap, upload the file from the GitHub release on the edit page).
- The site is behind a bot check that blocks browser and curl user agents; the script sends its own.
- If only the store step failed, fix the cause and use *Re-run failed jobs*: the GitHub release step
  is idempotent.
- Check the credentials without changing anything:
  `KDE_STORE_USERNAME=… KDE_STORE_PASSWORD=… scripts/kde-store-upload.sh --dry-run 2379427 dist/keeplet-*.plasmoid`
  (signs in and reads the edit page).
- Is it visible to Plasma: `curl 'https://api.kde-look.org/ocs/v1/content/data?search=Keeplet&format=json'`
  lists the product, and *Add Widgets → Get New Widgets…* finds "Keeplet".
