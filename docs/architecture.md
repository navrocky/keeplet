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

## Components
```
┌──────────────────── plasmoid (QML/JS) ───────────────────────┐
│ UI (contents/ui) ─ model.js ─ keepapi.js ─ XHR ─▶ googleapis.com/notes/v1
│                                  │
│                    auth ─────────┼─ XHR ─▶ android.clients.google.com/auth
│                                  └─ D-Bus (org.kde.plasma.workspace.dbus)
│                                        ─▶ org.kde.kwalletd6 (master token)
│ store.js ─ QtQuick.LocalStorage (cached nodes, sync version)
└──────────────────────────────────────────────────────────────┘
```
If stage 0 shows that `/auth` rejects Qt's TLS client, auth moves into a bundled static
helper `keeplet-auth` (Rust); see [decisions/0001-auth-helper.md](decisions/0001-auth-helper.md).

## Data flow
1. Login (once): user pastes `oauth_token` → exchanged for a long-lived **master token** → stored.
2. Each session: master token → short-lived **auth token** (~1 h), kept in memory only.
3. Sync: `POST /changes` with locally changed nodes and the last `toVersion`; server returns
   changed nodes and a new version. Details: [keep-protocol.md](keep-protocol.md).
4. UI edits mark nodes dirty; a debounced sync pushes them.

## Where data lives
| Data | Location |
|---|---|
| master token | KWallet folder `Keeplet`, or widget config if KWallet is disabled |
| auth token | memory only |
| notes cache, `toVersion` | `QtQuick.LocalStorage` (SQLite under `~/.local/share/plasmashell/QML/OfflineStorage/`) |
| settings | widget config (`~/.config/plasma-org.kde.plasma.desktop-appletsrc`) |
