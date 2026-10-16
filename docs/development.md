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
  - `tst_nodes`, `tst_keepapi`, `tst_gauth`, `tst_util`, `tst_workspace`, `tst_migration` — Model.
  - `tst_providers` — provider contract, Keep session on a fake transport, fake provider.
  - `tst_notesviewmodel`, `tst_accountsviewmodel` — ViewModels with fake sessions, cache and service.
  - Fixtures are hand-made and anonymized; never commit real notes.
- UI tests with synthetic mouse events on the real screens (`tests-ui/`, needs the Plasma QML modules on this
  machine; not run by `build.sh`): `scripts/test-ui.sh`.
- Manual end-to-end checklist before a release:
  1. Fresh install, sign in with an `oauth_token`.
  2. Notes appear; colors, pins, labels match keep.google.com.
  3. Edit/create/archive/trash in the widget → visible on keep.google.com and the phone.
  4. Edit on the web → visible in the widget after sync.
  5. Settings → Accounts → Sign Out → KWallet entry (or config key) removed. Add a Local notes account: notes survive a restart; deleting it asks for confirmation.
  6. Repeat 1–2 with KWallet disabled (fallback storage).
  7. Create a note and a list; edit, undo/redo, change color and labels; trash and restore; empty trash.
  8. Drag a note onto a label and onto "No label"; check it on the web; use the Undo notice.

## Stage 0 spikes
`spike/` holds the prototypes that decided the auth design
(see [decisions/0001-auth-helper.md](decisions/0001-auth-helper.md)):
- `spike/run-auth.sh` — full auth chain + one `/changes` from pure QML. Prompts for e-mail and
  `oauth_token` (hidden), keeps state in `~/.cache/keeplet-spike/state.json` (0600). `--reset` to start over.
- `spike/wallet.qml` — KWallet write/read/remove over D-Bus.

## Stage C0 spike: write protocol
`spike/run-write.sh` probes what the Keep API requires and returns when notes are **written**. It uses the
session saved by `run-auth.sh` and **writes to the real account**: it creates two notes titled
`keeplet write test (...)`, edits them (title, text, color, pin, archive, checklist items, the note's order, an existing label
on the test note only), trashes and deletes them. It never modifies a note it did not create and tries to
clean up after a failed step. Output contains no tokens and is saved to `~/.cache/keeplet-spike/write-report.txt`.

```sh
spike/run-write.sh --dry-run   # prints the payload and the plan, sends nothing
spike/run-write.sh             # asks for confirmation, then runs the scenario
```
The findings go into [keep-protocol.md](keep-protocol.md) before the write path (`mutations.js`) is built.
