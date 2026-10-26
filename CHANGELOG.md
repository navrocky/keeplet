# 0.9.1 (2026-10-26)

- Fix the widget failing to load on Kubuntu, Ubuntu and Debian without the QtQuick.LocalStorage module: it now says which package to install
- Fix the Keeplet icon missing from the widget list when installed from the KDE Store

# 0.9.0 (2026-10-25)

- Tells when a new version is out on the KDE Store; Update… installs it through Plasma's Get New Widgets dialog (can be turned off in the settings)
- Optional anonymous usage statistics: the widget asks once, a checkbox in the settings turns them on or off
- Link previews: resting the pointer on a web link shows a preview of the page in a popup (needs QtWebEngine); can be turned off in the settings
- Links in notes: web, e-mail and phone links are underlined on cards and in the editor; a click (Ctrl+click in the editor) opens one, the context menu opens or copies it
- Several accounts at once: one mixed list with your own order, an account chip on the cards, each account's labels and "No label" group in the rail, account choice for a new note
- Sign in with Google in a window (needs QtWebEngine); pasting a token remains as an alternative
- Labels: create, rename and delete them in the rail, or create and assign one right from the note editor
- Accounts in the settings: list with status and sign-out, add an account of any type
- Local account: notes kept only on this machine, no sign-in needed
- Checklists: multi-line items, to-do and collapsible Done sections, drag to reorder, keyboard editing (arrows, Enter, Shift+Enter, Backspace), clear done items, convert between note and list
- Copy a note as text from the card's context menu (checklists as Markdown tasks)
- Drag and drop: hold a card to pick it up, drop it between cards to reorder or on a label, Archive or Trash in the rail; dragging out of a label group removes that label
- Note editor with undo/redo, autosave, color picker and labels menu
- Notes list: create notes, context menu, undo notice, search, trash tools
- Group rail: All notes, labels, "No label", Archive and Trash; collapsible
- Note colors for light and dark themes
- Google Keep notes in a Plasma widget: sign in from the widget, notes synced and cached locally, token kept in KWallet
