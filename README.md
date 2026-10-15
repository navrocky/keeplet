# Keeplet

Google Keep notes in a KDE Plasma 6 widget, on your panel or desktop.

> **Status: early development — not usable yet.**
>
> Keeplet uses Google Keep's private (unofficial) API. Google may change it at any time,
> and using it is against Google's Terms of Service. Use at your own risk.

## Features
- Text notes and checklists (with nested items)
- Create, edit, pin, archive, trash
- Colors and labels
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

Requires KDE Plasma 6.

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
You can add more accounts from the widget menu (**Add account…**).

To sign out, open the widget menu (☰) → **Sign out <account>**. You can also revoke access in your
Google account → *Security* → *Your devices*.

## Use
- Click the widget to open your notes. Pinned notes are on top.
- The left rail lists groups: **All notes**, **No label** (notes you have not sorted yet), your labels,
  **Archive** and **Trash**. Click one to show only its notes; the button next to the search box
  collapses the rail to icons. With several accounts a switcher above the groups shows one account or all.
- Click a note to open it full width; the arrow in the corner takes you back to the list.
- The search box filters the notes of the selected group.

_Editing, creating notes, choosing colors and drag-and-drop into groups are in progress._

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
