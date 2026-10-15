import QtQuick
import "../../code/core/history.js" as History

// ViewModel of the open note: a working copy, undo/redo over everything in the note (title, text, items,
// color, labels, pin, archive, trash) and autosave through NotesViewModel. No visuals, no user-facing text.
// Closing the note resets the history.
//
// `notes` is the NotesViewModel (needs currentNoteKey, noteByKey, saveNote, removeNote, canWrite,
// capabilities, closeNote, labelsOf, writableAccounts).
QtObject {
    id: vm

    required property var notes

    // Pause after the last change before it is saved (ms) and the window in which typing counts as one
    // undo step; both are overridable for tests.
    property int saveDelay: 800
    property int coalesceWindow: 700
    property int historyLimit: 100

    // --- Output
    readonly property string noteKey: notes.currentNoteKey
    property var note: null          // working copy: provider-neutral note plus accountKey/key
    readonly property bool isOpen: note !== null
    property bool canUndo: false
    property bool canRedo: false
    // Trashed notes and read-only providers are view-only.
    readonly property bool editable: note !== null && !note.trashed && notes.canWrite(note.accountKey)
    readonly property bool trashed: note !== null && note.trashed
    readonly property var colors: note !== null && notes.capabilities(note.accountKey)
                                  ? notes.capabilities(note.accountKey).colors : []
    readonly property bool nestedItems: note !== null && !!notes.capabilities(note.accountKey)
                                        && !!notes.capabilities(note.accountKey).nestedItems

    // Labels of the note's account that can be switched on and off: [{id, name, on}]. Empty when the
    // provider has no labels.
    readonly property var labelChoices: {
        if (note === null)
            return []
        var caps = notes.capabilities(note.accountKey)
        if (!caps || caps.labels === "none")
            return []
        var on = {}
        note.labels.forEach(function (l) { on[l.id] = true })
        return notes.labelsOf(note.accountKey).map(function (l) {
            return { id: l.id, name: l.name, on: !!on[l.id] }
        }).sort(function (a, b) { return a.name.localeCompare(b.name) })
    }
    readonly property bool labelsSingle: note !== null && !!notes.capabilities(note.accountKey)
                                         && notes.capabilities(note.accountKey).labels === "single"

    // A new note that has not been stored yet may still be moved to another account.
    readonly property bool isNewUnsaved: note !== null && note.id === ""
    readonly property var accountChoices: isNewUnsaved ? notes.writableAccounts() : []

    // Asks the View to focus an item (after addItem).
    signal itemFocusRequested(int index)

    // --- Private
    property var _history: History.create({ limit: 100, window: 700 })
    property bool _unsaved: false

    property Timer _timer: Timer {
        interval: vm.saveDelay
        repeat: false
        onTriggered: vm._save()
    }

    // --- Commands: every command is one undo step (typing is coalesced per field)
    function setTitle(text) { _change("title", function (n) { n.title = text }) }
    function setText(text) { _change("text", function (n) { n.text = text }) }
    function setColor(name) { _change("", function (n) { n.color = name }) }
    function togglePinned() { _change("", function (n) { n.pinned = !n.pinned }) }
    function setArchived(archived) { _change("", function (n) { n.archived = !!archived }) }
    // Switches one label of the note on or off (single-category providers keep at most one).
    function toggleLabel(labelId) {
        var choice = labelChoices.filter(function (l) { return l.id === labelId })[0]
        if (!choice)
            return
        _change("", function (n) {
            if (choice.on) {
                n.labels = n.labels.filter(function (l) { return l.id !== labelId })
            } else {
                var added = { id: choice.id, name: choice.name }
                n.labels = labelsSingle ? [added] : n.labels.concat([added])
            }
        })
    }

    // Moves a new, not yet stored note to another account; labels belong to an account, so they are dropped.
    function setAccount(accountKey) {
        if (!isNewUnsaved || !notes.canWrite(accountKey) || note.accountKey === accountKey)
            return
        _change("", function (n) {
            n.accountKey = accountKey
            n.labels = []
        })
    }

    function setLabels(labels) {
        _change("", function (n) {
            n.labels = labels.map(function (l) { return { id: l.id, name: l.name } })
        })
    }

    function setItemText(index, text) {
        _change("item:" + index, function (n) { if (n.items[index]) n.items[index].text = text })
    }
    function toggleItem(index) {
        _change("", function (n) { if (n.items[index]) n.items[index].checked = !n.items[index].checked })
    }
    function setItemIndent(index, indent) {
        if (!nestedItems)
            return
        _change("", function (n) {
            if (n.items[index])
                n.items[index].indent = Math.max(0, Math.min(1, indent))
        })
    }
    // Inserts an empty item below `afterIndex` (-1: at the top) and asks the View to focus it.
    function addItem(afterIndex) {
        var at = afterIndex + 1
        _change("", function (n) {
            var indent = n.items[afterIndex] ? n.items[afterIndex].indent : 0
            n.items.splice(at, 0, { id: "", text: "", checked: false, indent: indent })
        })
        itemFocusRequested(at)
    }
    function removeItem(index) {
        _change("", function (n) { n.items.splice(index, 1) })
    }

    function undo() {
        var previous = History.undo(_history, _clone(note))
        if (previous)
            _adopt(previous)
    }
    function redo() {
        var next = History.redo(_history, _clone(note))
        if (next)
            _adopt(next)
    }

    // Moves the open note to the trash and closes it.
    function trash() {
        if (!editable)
            return
        _change("", function (n) { n.trashed = true })
        close()
    }
    function restore() {
        if (note === null || !note.trashed || !notes.canWrite(note.accountKey))
            return
        var n = _clone(note)
        History.record(_history, _clone(note), "", Date.now())
        n.trashed = false
        note = n
        _unsaved = true
        _save()
        _refreshFlags()
    }
    function deleteForever() {
        if (note === null)
            return
        _timer.stop()
        _unsaved = false
        notes.removeNote(note)
        notes.closeNote()
    }

    // Saves pending changes now.
    function flush() { _save() }

    // Saves and returns to the list.
    function close() {
        _save()
        notes.closeNote()
    }

    // --- Internals
    function _clone(o) { return JSON.parse(JSON.stringify(o)) }

    function _refreshFlags() {
        canUndo = History.canUndo(_history)
        canRedo = History.canRedo(_history)
    }

    function _change(key, fn) {
        if (!editable)
            return
        var before = _clone(note)
        var after = _clone(note)
        fn(after)
        if (JSON.stringify(after) === JSON.stringify(before))
            return
        History.record(_history, before, key, Date.now())
        note = after
        _unsaved = true
        _refreshFlags()
        _timer.restart()
    }

    // Switches the working copy to a snapshot from the history and schedules its save.
    function _adopt(snapshot) {
        note = snapshot
        _unsaved = true
        _refreshFlags()
        _timer.restart()
    }

    function _save() {
        _timer.stop()
        if (!_unsaved || note === null)
            return
        _unsaved = false
        // The note may have been deleted elsewhere while it was open: don't bring it back.
        if (note.id && notes.noteByKey(note.key) === null)
            return
        var key = notes.saveNote(note)
        if (!key)
            return
        var stored = notes.noteByKey(key)
        if (stored)
            _adoptIds(stored)
    }

    // Ids of new notes and items are generated by the provider; keep them in the working copy (not an undo step).
    function _adoptIds(stored) {
        if (note === null)
            return
        var n = _clone(note)
        n.id = stored.id
        n.key = stored.key
        n.accountKey = stored.accountKey
        if (stored.items.length === n.items.length) {
            for (var i = 0; i < n.items.length; i++)
                n.items[i].id = stored.items[i].id
        }
        note = n
    }

    function _load() {
        _timer.stop()
        _history = History.create({ limit: historyLimit, window: coalesceWindow })
        _unsaved = false
        var stored = noteKey ? notes.noteByKey(noteKey) : null
        note = stored ? _clone(stored) : null
        _refreshFlags()
    }

    onNoteKeyChanged: {
        // Leaving a note (also when it vanished) must not lose edits that are still waiting for the timer.
        if (_unsaved)
            _save()
        _load()
    }

    Component.onCompleted: _load()
    Component.onDestruction: _save()
}
