# AGENTS.md

Keeplet is a KDE Plasma 6 widget (plasmoid) that works as a Google Keep client.
It uses Google Keep's private mobile API (protocol ported from gkeepapi/gpsoauth).

## Hard constraints
- Widget is pure QML/JS, installable from KDE Store: no native code, no compiled QML plugins, no Python
  ([why it's enough](docs/decisions/0001-auth-helper.md)).
- Never log or print tokens (oauth_token, master token, auth token); mask them.
- Master token lives in KWallet when it is enabled, otherwise in the widget config (see [docs/auth.md](docs/auth.md)).

## Architecture rule: MVVM
- **Model** — `package/contents/code/*.js`: pure JS (state, protocol, auth). No QML items, no `i18n`.
- **ViewModel** — `package/contents/ui/viewmodel/*.qml`: `QtObject`s with state, derived lists and commands.
  No visual items, no user-facing strings (expose error *codes*). Dependencies are injected
  (`auth`, `cache`, `transport`) so they are unit-testable without Plasma.
- **View** — `package/contents/ui/views/*.qml`: layout and bindings only; call ViewModel commands,
  never talk to Model/network/storage directly. All `i18n()` lives here.
- `package/contents/ui/services/*.qml` wrap platform APIs (KWallet, LocalStorage) for the ViewModels.
- Details: [docs/architecture.md](docs/architecture.md).

## Commands
- `scripts/build.sh` — tests + lint + `dist/keeplet-<version>.plasmoid` (Docker/Podman, nothing else needed).
- `scripts/install.sh [file]` / `scripts/install.sh --remove` — install into the current user's Plasma.
- `scripts/dev.sh` — run `package/` in a window without building.
- `QT_QPA_PLATFORM=offscreen qmltestrunner6 -input tests` — fast local tests.

## Docs
- [docs/architecture.md](docs/architecture.md) — components and data flow
- [docs/auth.md](docs/auth.md) — auth chain, token storage
- [docs/keep-protocol.md](docs/keep-protocol.md) — Keep `/changes` API and node model
- [docs/plasmoid.md](docs/plasmoid.md) — `package/` layout, QML conventions, Plasma gotchas
- [docs/development.md](docs/development.md) — dev setup, install, testing, debugging
- [docs/release.md](docs/release.md) — versioning, CI, publishing
- [docs/decisions/](docs/decisions/) — architecture decision records
