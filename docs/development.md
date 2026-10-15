# Development

## Requirements
- KDE Plasma 6 (to run the widget).
- `docker` or `podman` and `git` (to build). Nothing else: tests, lint and packaging run in a container.
- Optional for a faster loop: `qmltestrunner6` (Qt 6 declarative tools), `plasmoidviewer` (plasma-sdk).

## Build
```sh
scripts/build.sh            # tests + qmllint + dist/keeplet-<version>.plasmoid + dist/SHA256SUMS
scripts/build.sh --no-test
```
The build image is `docker/Dockerfile`; `scripts/package.sh` is the in-container part.
Version comes from `git describe` (`v1.2.3` tag → `1.2.3`, otherwise `0.0.0-dev.<n>+<sha>`).

On SELinux hosts the container runs with `--security-opt label=disable` (repo files are not relabeled).

## Install into your Plasma
```sh
scripts/install.sh                      # newest dist/*.plasmoid (install or upgrade)
scripts/install.sh path/to/file.plasmoid
systemctl --user restart plasma-plasmashell   # reload if the widget is already on a panel/desktop
scripts/install.sh --remove             # uninstall
```
Then: right-click panel/desktop → *Add Widgets…* → *Keeplet*.
Installed files: `~/.local/share/plasma/plasmoids/io.github.navrocky.keeplet/`.

## Fast loop
```sh
scripts/dev.sh
```
Runs `package/` without building: `plasmoidviewer` if installed, else installs the
directory and opens it with `plasmawindowed`. Re-run after each QML change.

## Debugging
- Logs: `QT_FORCE_STDERR_LOGGING=1` (set by `dev.sh`), or for plasmashell: `journalctl --user -f | grep -i keeplet`.
- KWallet entries: KWalletManager → folder `Keeplet`.
- Never log tokens; mask them (first 8 chars + length).
- Offscreen smoke test (prints QML warnings/errors):
  `scripts/install.sh package && QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen timeout 8 plasmawindowed io.github.navrocky.keeplet`

## Tests
- Unit tests: `tests/tst_*.qml` (QtTest), run by `build.sh`, or locally:
  `QT_QPA_PLATFORM=offscreen qmltestrunner6 -input tests`.
- Manual end-to-end checklist before a release:
  1. Fresh install, sign in with an `oauth_token`.
  2. Notes appear; colors, pins, labels match keep.google.com.
  3. Edit/create/archive/trash in the widget → visible on keep.google.com and the phone.
  4. Edit on the web → visible in the widget after sync.
  5. Sign out → KWallet entry (or config key) removed.
  6. Repeat 1–2 with KWallet disabled (fallback storage).

## Stage 0 spikes
`spike/` holds the prototypes that decided the auth design
(see [decisions/0001-auth-helper.md](decisions/0001-auth-helper.md)):
- `spike/run-auth.sh` — full auth chain + one `/changes` from pure QML. Prompts for e-mail and
  `oauth_token` (hidden), keeps state in `~/.cache/keeplet-spike/state.json` (0600). `--reset` to start over.
- `spike/wallet.qml` — KWallet write/read/remove over D-Bus.
