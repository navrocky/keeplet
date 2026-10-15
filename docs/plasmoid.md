# Plasmoid package

```
package/
├── metadata.json                  KPackage metadata; Version is stamped by the build
└── contents/
    ├── code/                      Model: pure JS (.pragma library), no UI
    │   ├── core/                  notes.js, workspace.js, errors.js, util.js, migration.js
    │   └── providers/             contract.js, registry.js, fake.js, keep/{index,gauth,keepapi,nodes}.js
    ├── ui/
    │   ├── main.qml               PlasmoidItem: wires services and ViewModels, picks the View
    │   ├── viewmodel/             AccountsViewModel, NotesViewModel (QtObject, no visuals)
    │   ├── views/                 SignInView, NotesRoot (navigation), NotesScreen, LabelRail, NoteScreen,
    │   │                          NoteCard, ColorPicker, keepColors.js (layout + bindings)
    │   ├── services/              LocalDb, SecretStore, AccountsService, NotesCache (platform APIs)
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
- Accounts and secrets are global (see [decisions/0002-accounts-and-storage.md](decisions/0002-accounts-and-storage.md));
  `config/main.xml` keeps only per-instance data plus the legacy single-account keys read once by the migration.
  Don't declare legacy keys as `cfg_*` in config pages: the dialog writes every declared `cfg_*` back on Apply.
- Properties are assigned in arbitrary order when an object is created: don't call a method that needs an injected
  dependency from `onXxxChanged` of another property; use `Component.onCompleted`.
- Don't name a property the same as the id you bind it to (`Foo { auth: auth }` is a binding loop).

## Colors
- Providers list the color names they support in `capabilities.colors` (empty = none; the first entry is
  the "no color" default). Keep: `DEFAULT, RED, ORANGE, YELLOW, GREEN, TEAL, BLUE, CERULEAN, PURPLE, PINK, BROWN, GRAY`.
- `views/keepColors.js` maps a name to a shade for the light (pastel) or dark (muted) palette and picks readable
  text; `DEFAULT`/unknown names use the theme. `dark` comes from the theme background luminance
  (`KeepColors.isDark(Kirigami.Theme.backgroundColor)`); `NoteCard`, `NoteScreen` and `ColorPicker` expose it as an
  overridable `dark` property for previews and tests. `tests/tst_keepcolors.qml` enforces WCAG contrast >= 4.5.
- `ColorPicker` only emits `picked(name)`; applying the color needs the write path (stage C/D).

## Gotchas
- `console.log` goes to journald unless `QT_FORCE_STDERR_LOGGING=1` is set.
- Offscreen preview harnesses (`QT_QPA_PLATFORM=offscreen qml6 harness.qml` + `grabToImage`) render no icons unless the
  harness also loads the Plasma views (e.g. `NotesRoot`); a bare `Kirigami.Icon` stays empty there. Not a widget bug.
- In a `Repeater` delegate, `required property modelData` must be declared on the delegate's root item.
- Synchronous `file://` PUT via XHR truncates the file and writes nothing; use async (only relevant for tooling).
- plasmashell caches QML of loaded widgets; restart it after reinstalling (see [development.md](development.md)).
- `Plasma5Support` `executable` DataSource runs shell commands; avoid passing secrets through it (visible in `ps`).
