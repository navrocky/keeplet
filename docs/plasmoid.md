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
    │   ├── viewmodel/             AccountsViewModel, NotesViewModel, NoteEditorViewModel (QtObject, no visuals)
    │   ├── views/                 SignInView, NotesRoot (navigation), NotesScreen, LabelRail, NoteScreen (editor),
    │   │                          NoteCard, ColorPicker, keepColors.js (layout + bindings)
    │   ├── services/              LocalDb, SecretStore, AccountsService, NotesCache, BrowserSignIn (platform APIs)
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

## Performance notes
- `tests-ui/bench_checklist.qml` (run with `qmltestrunner6 -input tests-ui/bench_checklist.qml`, prints `BENCH` lines) times add/remove/toggle/flush on a 40-item list inside a 1500-note account (6000 nodes).
  Before/after: add item 46 -> 8 ms, remove 49 -> 3 ms, the save 0.8 s after the last change 275 -> 8 ms.
- After a local edit `NotesViewModel._afterWrite(a, noteId)` rebuilds only that note (`session.note`, `Nodes.buildNote`) instead of every note
  (`Nodes.buildNotes` costs ~120-170 ms for 6000 nodes); sync results and structural changes still rebuild everything.

## Storage is asynchronous
- Services (`LocalDb`, `NotesCache`, `AccountsService`, `SecretStore`) return **Promises**; nothing in a ViewModel may wait for
  storage. `LocalDb` queues operations and runs one per event-loop turn, coalesces writes to one key, answers a read of a key
  with a pending write from memory, and `drain()`s the queue when it is destroyed. `NotesViewModel` loads an account's cache,
  shows it, and only then starts the first sync; the cache snapshot is written after `cacheDelay` of quiet and flushed on destruction.
- SQLite itself still runs on the UI thread: `QtQuick.LocalStorage` has only a synchronous API and its module cannot be
  imported in a `WorkerScript` (checked on Qt 6.11). Measured cost of that: ~5 ms to write a 1.6 MB snapshot (5000 notes),
  `JSON.stringify` of it ~21 ms. If it ever matters, only `LocalDb` has to change.
- Test doubles for services must return Promises too (see `tests/tst_accountsviewmodel.qml`); `tests-ui/tst_localdb.qml` runs the real `LocalDb`.

## Colors
- Providers list the color names they support in `capabilities.colors` (empty = none; the first entry is
  the "no color" default). Keep: `DEFAULT, RED, ORANGE, YELLOW, GREEN, TEAL, BLUE, CERULEAN, PURPLE, PINK, BROWN, GRAY`.
- `views/keepColors.js` maps a name to a shade for the light (pastel) or dark (muted) palette and picks readable
  text; `DEFAULT`/unknown names use the theme. `dark` comes from the theme background luminance
  (`KeepColors.isDark(Kirigami.Theme.backgroundColor)`); `NoteCard`, `NoteScreen` and `ColorPicker` expose it as an
  overridable `dark` property for previews and tests. `tests/tst_keepcolors.qml` enforces WCAG contrast >= 4.5.
- `ColorPicker` only emits `picked(name)`; `NoteScreen` hosts it in a popup and calls `NoteEditorViewModel.setColor`.

## Editor
- `NoteEditorViewModel` keeps a working copy of the open note, records undo steps in `core/history.js`
  (typing coalesces per field, other actions are separate steps) and saves through `NotesViewModel.saveNote`
  after `saveDelay`, on close and when the open note changes. The history is dropped when the note closes.
- Views never recreate text fields while typing: the checklist `Repeater` uses the item *count* as its model and
  each delegate reads its item by index, so focus survives every keystroke. Text fields bind to the working copy and
  write back only when the text really differs (`onTextEdited` / equality guard), which also makes undo update them.
- Undo/redo keys are handled in the fields' `Keys.onPressed` (text controls swallow the standard shortcuts).
- A new note is a *draft* in `NotesViewModel` (`draftKey` = `"<new>"`): it is created in the provider on the first
  change, the editor keeps its history, and the key stays `"<new>"` while the editor is open.

- Checklist: `NoteEditorViewModel` exposes `openIndexes` / `doneIndexes` (indexes into `note.items`; they change only on
  structure/check changes, not while typing). The array itself is never split, so a checked item keeps its relative place
  when unchecked. `NoteScreen` positions rows by hand (one delegate per item, `y` from section and place): checking,
  dragging (handle at the row start, `moveItemInSection`) and folding the Done section are animations of `y`, `opacity`
  and height. Items are multi-line (`TextArea`, Enter = next item, Shift+Enter = line break); rows are as tall as their text but not below the one-line height, rows report their heights and `tops` stacks them. Rows are **identity-stable**: every item has a client-side `uid` (`NoteEditorViewModel.itemUids`, never saved) and `NoteScreen` keeps a `ListModel` of rows in step with it (insert/remove/move), so an insert creates one row and the others just slide (their `y` follows the item's new place) instead of being rebound to other items.
- `convertToList` / `convertToText` (capability `convertType`) switch the note type, keeping check marks as Markdown task lines (`- [x] text`, `core/checklist.js`; plain lines when nothing is checked); `asText` feeds "Copy as text"; `clearDone` removes checked items.

## List interactions
- Pointer handling is on the **list**, not on the cards: a `TapHandler` (open), a right-button `TapHandler`
  (context menu) and one `DragHandler` with only the x axis enabled (so vertical drags keep scrolling). Delegates
  are destroyed when they scroll out of view; handlers on them would lose the end of a running drag.
- `DragLayer` is the floating ghost. It is a **sibling** of the screen's layout (never inside it: a full-size
  child of a layout takes the room of the content) and is invisible unless a drag runs. A drag always ends:
  drop, cancel (selection, account filter or open note changed) or the watchdog.
- Drop targets: rail rows are `DropArea`s that ask `NotesViewModel.canDrop` and call `dropNote`; if nobody takes
  the note and the pointer is over the list, `moveNote` puts it at the insertion point (`insertBefore` /
  `insertIndex` in `NotesScreen`; delegates open a gap, a footer item opens one at the end).
- The carried card's slot collapses (height animation) so the other cards close the gap; the card keeps its size
  inside the slot. While carrying, rail rows scale up if they can take the note and dim if not.
- Edge scrolling: a 16 ms timer moves `contentY` while the pointer is within `scrollZone` of the list's top or
  bottom (also above/below it), faster towards the edge.
- Everything else goes through `NotesViewModel` commands; trash/archive/drop are undoable via `lastAction`/`undoLast`.
- `scripts/test-ui.sh` runs `tests-ui/` with synthetic mouse events on the real screens (needs the Plasma QML modules).

## Gotchas
- `console.log` goes to journald unless `QT_FORCE_STDERR_LOGGING=1` is set.
- Offscreen preview harnesses (`QT_QPA_PLATFORM=offscreen qml6 harness.qml` + `grabToImage`) render no icons unless the
  harness also loads the Plasma views (e.g. `NotesRoot`); a bare `Kirigami.Icon` stays empty there. Not a widget bug.
- In a `Repeater` delegate, `required property modelData` must be declared on the delegate's root item.
- Synchronous `file://` PUT via XHR truncates the file and writes nothing; use async (only relevant for tooling).
- plasmashell caches QML of loaded widgets; restart it after reinstalling (see [development.md](development.md)).
- `Plasma5Support` `executable` DataSource runs shell commands; avoid passing secrets through it (visible in `ps`).
