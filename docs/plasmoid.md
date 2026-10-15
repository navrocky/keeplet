# Plasmoid package

```
package/
├── metadata.json            KPackage metadata; Version is stamped by the build
└── contents/
    ├── ui/main.qml          PlasmoidItem: compact (icon) + full (sign-in or notes) representation
    ├── ui/Auth.qml          account state (sign in/out, token cache)
    ├── ui/SecretStore.qml   KWallet / config fallback
    ├── ui/SignInView.qml    sign-in form shown in the popup
    ├── ui/configGeneral.qml settings page
    ├── ui/*.qml             (stage 2+) NoteCard, NoteEditor, ListNoteEditor
    ├── code/*.js            util.js, keepapi.js, model.js, store.js (`.pragma library` where stateless)
    └── config/              main.xml (KConfigXT schema), config.qml (config pages)
```

Plugin id: `io.github.navrocky.keeplet` (the `org.kde.*` namespace is reserved for KDE projects).

## Conventions
- Only modules shipped with Plasma 6 / Qt 6 / Kirigami. No compiled plugins.
- HTTP via `XMLHttpRequest`; JSON in/out. Don't use `Content-Type` charset tricks: Qt appends `;charset=UTF-8`.
- D-Bus via `org.kde.plasma.workspace.dbus` (see [auth.md](auth.md) for its quirks).
- User-visible strings through `i18n()`.
- Sign-in lives in the popup, not in the settings dialog: the dialog writes every declared
  `cfg_*` back on Apply and could resurrect a token after sign-out. So account entries in
  `config/main.xml` are never declared as `cfg_*` in config pages.
- Don't name a property the same as the id you bind it to (`Foo { auth: auth }` is a binding loop).

## Gotchas
- `console.log` goes to journald unless `QT_FORCE_STDERR_LOGGING=1` is set.
- Synchronous `file://` PUT via XHR truncates the file and writes nothing; use async (only relevant for tooling).
- plasmashell caches QML of loaded widgets; restart it after reinstalling (see [development.md](development.md)).
- `Plasma5Support` `executable` DataSource runs shell commands; avoid passing secrets through it (visible in `ps`).
