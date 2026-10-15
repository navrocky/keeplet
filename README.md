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
4. Right-click Keeplet → *Configure Keeplet…* → enter your Google e-mail, paste the token, click **Sign in**.

The token works once; Keeplet exchanges it for a long-lived key and stores it in KWallet
(or in the widget settings if KWallet is disabled — the settings page shows which).
Don't share that key: it gives full access to your Google account.

To sign out, click **Sign out** in the settings. You can also revoke access in your
Google account → *Security* → *Your devices*.

## Use
- Click the widget to open your notes. Pinned notes are on top.
- **New note / New list** buttons at the top.
- Click a note to edit it; changes save automatically.
- Note menu: pin, color, labels, archive, delete.
- Search box filters by text; the label selector filters by label.
- Archived and deleted notes are under the view selector.

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
