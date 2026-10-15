# Architecture

## Why the private API
Google's official Keep API (`keep.googleapis.com`) is available only to Google Workspace
domains (service account + domain-wide delegation), cannot update notes and has no labels,
colors or pinning. Keeplet therefore talks to the private API used by the Android app
(`https://www.googleapis.com/notes/v1/`), as reverse-engineered by
[gkeepapi](https://github.com/kiwiz/gkeepapi) (MIT). Authentication follows
[gpsoauth](https://github.com/simon-weber/gpsoauth) (MIT).

This API is unofficial: it may break when Google changes it, and using it is against
Google's Terms of Service.

## Components (MVVM)
```
 View                ViewModel                 Model / services
 ────                ─────────                 ────────────────
 SignInView   ─────▶ AuthViewModel   ───────▶  gauth.js ── XHR ─▶ android.clients.google.com/auth
                          │                    SecretStore ── D-Bus ─▶ kwalletd6 (master token)
 NotesView    ─────▶ NotesViewModel  ───────▶  keepapi.js ── XHR ─▶ googleapis.com/notes/v1
  └ NoteCard              │                    nodes.js   (node graph → notes, pure)
                          └────────────────▶   NotesCache ── LocalStorage (SQLite snapshot)
```
- Views bind to ViewModel properties and call its commands; they hold no logic.
- ViewModels never import visual types and never produce user-facing text (errors are codes).
- Model code is pure JS (`.pragma library`) and is unit-tested in `tests/`.
No native code: stage 0 showed that both `/auth` and `/changes` work from QML XHR
([decisions/0001-auth-helper.md](decisions/0001-auth-helper.md)).

## Data flow
1. Login (once): user pastes `oauth_token` → exchanged for a long-lived **master token** → stored.
2. Each session: master token → short-lived **auth token** (~1 h), kept in memory only.
3. Sync (`NotesViewModel.refresh`): `POST /changes` with the last `toVersion`, repeated while the
   server says `truncated`; changes are merged into the state (`nodes.applyChanges`) and the
   whole state is snapshotted to the cache. Details: [keep-protocol.md](keep-protocol.md).
4. On start the cached snapshot is shown immediately, then a sync runs; then it repeats on a timer
   (`syncInterval`) and on demand. A 401 refreshes the auth token and retries once.
5. (Stage 3) UI edits mark nodes dirty; a debounced sync pushes them.

## Where data lives
| Data | Location |
|---|---|
| master token | KWallet folder `Keeplet`, or widget config if KWallet is disabled |
| auth token | memory only |
| notes snapshot (raw nodes, labels, `toVersion`) | `QtQuick.LocalStorage`, one JSON row per account (SQLite under `~/.local/share/plasmashell/QML/OfflineStorage/`) |
| settings | widget config (`~/.config/plasma-org.kde.plasma.desktop-appletsrc`) |
