# Plasmoid package

```
package/
├── metadata.json            KPackage metadata; Version is stamped by the build
└── contents/
    ├── ui/main.qml          PlasmoidItem: compact (icon) + full (notes) representation
    ├── ui/*.qml             NoteCard, NoteEditor, ListNoteEditor, Auth, config pages
    ├── code/*.js            util.js, keepapi.js, model.js, store.js (`.pragma library` where stateless)
    └── config/              main.xml (KConfigXT schema), config.qml (config pages)
```

Plugin id: `io.github.navrocky.keeplet` (the `org.kde.*` namespace is reserved for KDE projects).

## Conventions
- Only modules shipped with Plasma 6 / Qt 6 / Kirigami. No compiled plugins.
- HTTP via `XMLHttpRequest`; JSON in/out. Don't use `Content-Type` charset tricks: Qt appends `;charset=UTF-8`.
- D-Bus via `org.kde.plasma.workspace.dbus` (see [auth.md](auth.md) for its quirks).
- User-visible strings through `i18n()`.

## Gotchas
- `console.log` goes to journald unless `QT_FORCE_STDERR_LOGGING=1` is set.
- Synchronous `file://` PUT via XHR truncates the file and writes nothing; use async (only relevant for tooling).
- plasmashell caches QML of loaded widgets; restart it after reinstalling (see [development.md](development.md)).
- `Plasma5Support` `executable` DataSource runs shell commands; avoid passing secrets through it (visible in `ps`).
