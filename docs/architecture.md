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
 View                ViewModel                  Model / services
 ────                ─────────                  ────────────────
 SignInView   ─────▶ AccountsViewModel ───────▶ providers/registry.js ─▶ provider.signIn / createSession
                          │                     AccountsService ─▶ LocalDb (registry) + SecretStore (KWallet / LocalDb)
 NotesView    ─────▶ NotesViewModel   ───────▶  session.sync/notes/labels  (one session per account)
  └ NoteCard              │                     core/workspace.js (merge, filter, sort)
                          └────────────────▶    NotesCache ─▶ LocalDb (snapshot per account)
```
- Views bind to ViewModel properties and call its commands; they hold no logic.
- ViewModels never import visual types and never produce user-facing text (errors are codes).
- Model code is pure JS (`.pragma library`) and is unit-tested in `tests/`.
- Providers are pluggable ([providers.md](providers.md)); Google Keep is one of them.
- Navigation state (selected group, account filter, open note, collapsed rail) lives in `NotesViewModel`;
  `NotesRoot` only follows `currentNoteKey` with a `StackView` and animated transitions.
- The rail is built in the ViewModel (`rail`, `accountTabs`): groups are "All notes" (always first),
  "No label" (notes without labels; with several accounts shown each account has its own under its header),
  labels (under per-account headers when several accounts are shown),
  Archive, Trash. With one account the rail is flat and the account switcher is not shown.
  Accounts whose provider has `labelEdit` also get a "New label" button (`+`, no caption) in their header when accounts are
  grouped, or a "New label" row when the rail is flat (an account without labels still gets its header); a label's context menu (right click / long press) renames or deletes it, and the note editor's label
  picker has "New label…". The ViewModel validates names (`labelNameError`), the View only shows the dialogs.
No native code: stage 0 showed that both `/auth` and `/changes` work from QML XHR
([decisions/0001-auth-helper.md](decisions/0001-auth-helper.md)).

## Data flow
1. Sign in (once per account): the provider exchanges the user's credentials for a long-lived secret
   (Keep: `oauth_token` → **master token**), which is stored; the account is added to the global registry.
2. Each widget start: accounts in scope are loaded, secrets read, one **session** per account created
   (Keep: master token → short-lived **auth token** (~1 h), kept in memory only).
3. Sync (`NotesViewModel.refresh`, per account, independently): `session.sync(state)`; for Keep that is
   `POST /changes` with the last `toVersion`, repeated while `truncated`
   ([keep-protocol.md](keep-protocol.md)). The state is snapshotted to the cache.
4. On start each account's cached snapshot is read asynchronously and shown, then a sync runs; then it repeats on a timer
   (`syncInterval`) and on demand. A 401 refreshes the auth token and retries once (inside the provider).
5. Writing: a View hands an edited note to `NotesViewModel.saveNote` → `session.commit` applies it to the
   provider state at once (optimistic) and queues it → the state is cached → after `writeDelay` of quiet the
   queue is pushed by `session.sync`. A failed push keeps the queue (it is part of the cached state), so edits made
   offline survive restarts and are sent later. `unsynced` tells the View how many edits are waiting.

## Where data lives
| Data | Location |
|---|---|
| account registry | `LocalDb` (`QtQuick.LocalStorage` SQLite under `~/.local/share/plasmashell/QML/OfflineStorage/`), **global** |
| secrets (master token) | KWallet folder `Keeplet`, key `<providerId>:<accountId>`; without KWallet the same `LocalDb`, **global** |
| auth token | memory only |
| notes snapshot (provider state) | `LocalDb`, one JSON row per account, **global** |
| which accounts this widget shows, sync interval | widget config (`~/.config/plasma-org.kde.plasma.desktop-appletsrc`), **per instance** |

Rationale and trade-offs: [decisions/0002-accounts-and-storage.md](decisions/0002-accounts-and-storage.md).
