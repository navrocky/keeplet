# Plasmoid package

```
package/
├── metadata.json                  KPackage metadata; Version is stamped by the build
└── contents/
    ├── code/                      Model: pure JS (.pragma library), no UI
    │   ├── util.js                key=value parsing, form encoding
    │   ├── gauth.js               gpsoauth port (exchange_token, perform_oauth)
    │   ├── keepapi.js             /changes transport, pagination, full resync
    │   └── nodes.js               node graph state, applyChanges, buildNotes/buildLabels
    ├── ui/
    │   ├── main.qml               PlasmoidItem: wires ViewModels, picks the View
    │   ├── viewmodel/             AuthViewModel, NotesViewModel (QtObject, no visuals)
    │   ├── views/                 SignInView, NotesView, NoteCard (layout + bindings)
    │   ├── services/              SecretStore (KWallet/config), NotesCache (LocalStorage)
    │   └── configGeneral.qml      settings page
    └── config/                    main.xml (KConfigXT schema), config.qml (config pages)
```

Plugin id: `io.github.navrocky.keeplet` (the `org.kde.*` namespace is reserved for KDE projects).

## Conventions
- Only modules shipped with Plasma 6 / Qt 6 / Kirigami. No compiled plugins.
- HTTP via `XMLHttpRequest`; JSON in/out. Don't use `Content-Type` charset tricks: Qt appends `;charset=UTF-8`.
- D-Bus via `org.kde.plasma.workspace.dbus` (see [auth.md](auth.md) for its quirks).
- MVVM layering rules are in [architecture.md](architecture.md): `i18n()` only in Views; ViewModels
  report errors as codes; dependencies are injected as `var` properties so tests can fake them.
- ViewModel tests import the `viewmodel/` directory but must not pull in `services/` (they need
  D-Bus / LocalStorage modules that the build image doesn't have).
- Sign-in lives in the popup, not in the settings dialog: the dialog writes every declared
  `cfg_*` back on Apply and could resurrect a token after sign-out. So account entries in
  `config/main.xml` are never declared as `cfg_*` in config pages.
- Don't name a property the same as the id you bind it to (`Foo { auth: auth }` is a binding loop).

## Gotchas
- `console.log` goes to journald unless `QT_FORCE_STDERR_LOGGING=1` is set.
- Synchronous `file://` PUT via XHR truncates the file and writes nothing; use async (only relevant for tooling).
- plasmashell caches QML of loaded widgets; restart it after reinstalling (see [development.md](development.md)).
- `Plasma5Support` `executable` DataSource runs shell commands; avoid passing secrets through it (visible in `ps`).
