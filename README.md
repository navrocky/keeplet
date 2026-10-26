# Keeplet

Google Keep notes in a KDE Plasma 6 widget, on your panel or desktop.

> **Status: early development — not usable yet.**
>
> Keeplet uses Google Keep's private (unofficial) API. Google may change it at any time,
> and using it is against Google's Terms of Service. Use at your own risk.

## Features
- Text notes and checklists (with nested items)
- Create, edit, pin, archive, trash, with undo/redo
- Drag a note onto a group to label it
- Colors (light and dark theme) and labels
- Search and label filter
- Images in notes (view only)
- Offline cache; syncs in the background and after every edit
- Token stored in KWallet when it's enabled

## Install
**From KDE Store:** right-click the panel or desktop → *Add Widgets…* → *Get New Widgets…* →
*Download New Plasma Widgets* → search for **Keeplet** → *Install*.

**From a file:** download `keeplet-X.Y.Z.plasmoid` from
[Releases](../../releases), then:
```sh
kpackagetool6 -t Plasma/Applet -i keeplet-X.Y.Z.plasmoid
```
Then add it: right-click the panel or desktop → *Add Widgets…* → *Keeplet*.

Requires KDE Plasma 6 and the Qt module QtQuick.LocalStorage. Kubuntu, Ubuntu and Debian ship it separately
(the widget tells you when it is missing):
```sh
sudo apt install qml6-module-qtquick-localstorage
```

**Updates:** when a new version is out on the KDE Store, the widget says so; **Update…** opens Plasma's
*Get New Widgets* dialog on Keeplet, and the new version starts after Plasma is restarted or on the next
login. Installed from the KDE Store, Keeplet is also updated by *Discover*. The check (once a day, on
store.kde.org) can be turned off in the widget settings → General → *Updates*.

## Set up
Google no longer allows third-party apps to log in with a password, so you sign in once in
your browser and hand Keeplet a one-time token:

1. Open <https://accounts.google.com/EmbeddedSetup> in a desktop browser and sign in.
   Continue until the page stops loading or shows an error — that's expected.
2. Open developer tools (`F12`) → **Application** (Chrome) or **Storage** (Firefox) → **Cookies** →
   `https://accounts.google.com`.
3. Copy the value of the **`oauth_token`** cookie (starts with `oauth2_4/`).
4. Click the Keeplet icon, enter your Google e-mail, paste the token and click **Sign In**.

The token works once; Keeplet exchanges it for a long-lived key and stores it in KWallet.
**If KWallet is disabled, the key is stored in a local database file in your home directory
(`~/.local/share/plasmashell/QML/OfflineStorage/`) — enable KWallet if other users can read your files.**
Don't share that key: it gives full access to your Google account.

Accounts are shared by all Keeplet widgets: sign in once, every new widget shows your notes.
Accounts are managed in the widget settings (menu ☰ → **Settings…**, page **Accounts**): the list shows every
account with its type and status, **Add Account…** lets you pick the type, and **Sign Out** removes an account.
You can have several Google Keep accounts at once. You can also revoke access in your Google account →
*Security* → *Your devices*.

### Local notes
If you cannot or do not want to use Google Keep, add an account of the type **Local notes**: no sign-in,
the notes live only on this computer (in the same local database file as above, unencrypted). Deleting
such an account deletes its notes; there is no backup or export yet.

## Use
- Click the widget to open your notes. Pinned notes are on top.
- The left rail lists groups: **All notes**, **No label** (notes you have not sorted yet), your labels,
  **Archive** and **Trash**. Click one to show only its notes; the button next to the search box
  collapses the rail to icons. With several accounts a switcher above the groups shows one account or all.
- Click a note to open it full width; the arrow in the corner takes you back to the list.
- Edit the title, the text or the checklist items right away; changes are saved automatically a moment after
  you stop typing and when you leave the note. Offline edits are kept and sent when the connection is back.
- **Undo / Redo** (buttons or `Ctrl+Z`, `Ctrl+Shift+Z`) revert and restore anything in the open note: text,
  items, color, pin. The history is dropped when you leave the note.
- The color button opens the palette; the pin button pins the note; the **⋮** menu archives it or moves it to the trash.
  A note in the trash is read-only until you restore it or delete it for good.
- The **+** button creates a note or a list (in the account and label you are looking at).
- **Drag a note to the left** onto a group in the rail to put it into that label; drop it on **No label**
  to remove its labels. While you carry it the note shrinks to a chip, the groups that can take it grow and
  the others dim. A short **Undo** notice follows. Hold the note near the top or bottom edge of the list to
  scroll it.
- **Drop a note between two others** to put it there (manual order, saved in Keep). The other notes move
  apart and show the place. This works while the list shows one account, no search and not the trash;
  pinned notes stay among the pinned ones.
- Right-click a note for pin, color, archive and trash. In the trash: restore, delete forever, or **Empty trash**.
- The tag button in an open note switches its labels on and off.
- The search box filters the notes of the selected group.

_Creating and renaming labels, and reordering checklist items, are not available yet._

## Privacy
Keeplet talks only to the services of your accounts and, once a day, to store.kde.org to see if a new
version is out (can be turned off). Optionally, and only if you agree when the widget asks,
it sends anonymous usage statistics (which features are used, error codes, widget version and language;
never note contents, labels or account details) to Google Analytics. You can turn it off in the widget
settings → General → *Statistics*. Details: [docs/analytics.md](docs/analytics.md).

## Uninstall
Right-click the widget → *Remove*, then:
```sh
kpackagetool6 -t Plasma/Applet -r io.github.navrocky.keeplet
```
Also delete the `Keeplet` folder in KWalletManager if you used KWallet.

## Credits
Keep protocol and authentication are based on [gkeepapi](https://github.com/kiwiz/gkeepapi)
and [gpsoauth](https://github.com/simon-weber/gpsoauth) (both MIT).

License: [MIT](LICENSE). Developers: see [docs/development.md](docs/development.md).
