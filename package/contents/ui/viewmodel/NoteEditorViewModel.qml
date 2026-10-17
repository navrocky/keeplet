import QtQuick
import "../../code/core/history.js" as History
import "../../code/core/checklist.js" as Checklist

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

    readonly property bool canConvert: editable && !!notes.capabilities(note.accountKey)
                                       && !!notes.capabilities(note.accountKey).convertType

    // Checklist split into sections: indexes into note.items of the unchecked / checked items, in item order
    // (so an item keeps its relative place when it is checked and unchecked again). They change only when
    // an item is added, removed, moved or (un)checked, never while typing, so Views can use them as models.
    // Stable id of every item of the open note (client side only, never saved): lets a View keep one row per item
    // while items are inserted, removed or moved. Changes only when that sequence changes.
    property var itemUids: []
    function itemIndexOf(uid) {
        if (note === null)
            return -1
        for (var i = 0; i < note.items.length; i++) {
            if (note.items[i].uid === uid)
                return i
        }
        return -1
    }
    property var openIndexes: []
    property var doneIndexes: []
    readonly property bool hasDone: doneIndexes.length > 0

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

    // Whether the account of the note lets the user create labels (the picker offers "New label").
    readonly property bool canCreateLabel: note !== null && notes.canEditLabels(note.accountKey)

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

    // Why `name` cannot be a new label of the note's account: "" | "empty" | "exists".
    function labelNameError(name) {
        return note === null ? "empty" : notes.labelNameError(note.accountKey, name)
    }

    // Creates a label in the note's account and puts the note into it (one undo step for the assignment;
    // the label itself stays). Returns "" or the reason it failed ("empty", "exists", "unsupported").
    function createLabel(name) {
        if (note === null || !canCreateLabel)
            return "unsupported"
        var err = notes.labelNameError(note.accountKey, name)
        if (err !== "")
            return err
        var made = notes.createLabel(note.accountKey, name)
        if (!made)
            return "unsupported"
        _change("", function (n) {
            var added = { id: made.id, name: made.name }
            n.labels = labelsSingle ? [added] : n.labels.concat([added])
        })
        return ""
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
    // Inserts an empty item above `index` (same indent) and asks the View to focus it.
    function addItemAbove(index) {
        if (!note || !note.items[index])
            return
        _change("", function (n) {
            n.items.splice(index, 0, { id: "", text: "", checked: false, indent: n.items[index].indent })
        })
        itemFocusRequested(index)
    }
    function removeItem(index) {
        _change("", function (n) { n.items.splice(index, 1) })
    }
    // Removes every checked item (with the sub-items of a removed item).
    function clearDone() {
        _change("", function (n) {
            var parentGone = false
            n.items = n.items.filter(function (it) {
                if (it.indent > 0)
                    return !parentGone && !it.checked
                parentGone = it.checked
                return !it.checked
            })
        })
    }

    // Moves an item (with its sub-items) within the section it is in: `fromPos` and `toPos` are positions in
    // openIndexes (done = false) or doneIndexes (done = true).
    function moveItemInSection(done, fromPos, toPos) {
        var list = done ? doneIndexes : openIndexes
        if (fromPos === toPos || fromPos < 0 || toPos < 0 || fromPos >= list.length || toPos >= list.length)
            return
        var from = list[fromPos]
        var ref = list[toPos]
        _change("", function (n) {
            function blockLength(i) {
                var j = i + 1
                if (n.items[i].indent > 0)
                    return 1
                while (j < n.items.length && n.items[j].indent > 0)
                    j++
                return j - i
            }
            var refItem = n.items[ref]
            var block = n.items.splice(from, blockLength(from))
            var at = n.items.indexOf(refItem)
            if (toPos > fromPos)
                at += blockLength(at)
            if (at === 0)
                block[0].indent = 0
            n.items.splice.apply(n.items, [at, 0].concat(block))
        })
    }

    // Text note -> checklist: every non-empty line becomes an item; "[x] ..." / "- [ ] ..." lines carry their check mark.
    function convertToList() {
        if (!canConvert || note.type === "LIST")
            return
        _change("", function (n) {
            var items = Checklist.fromText(n.text, nestedItems)
            n.type = "LIST"
            n.items = items.length > 0 ? items : [{ id: "", text: "", checked: false, indent: 0 }]
            n.text = ""
        })
    }
    // Checklist -> text note: one line per item, "- [x] ..." when anything is checked, plain lines otherwise.
    function convertToText() {
        if (!canConvert || note.type !== "LIST")
            return
        _change("", function (n) {
            n.type = "NOTE"
            n.text = Checklist.toText(n.items, false)
            n.items = []
        })
    }
    // The note as text for the clipboard: title, then the body (checklists with Markdown check marks).
    function asText() {
        if (note === null)
            return ""
        return Checklist.noteText(note)
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

    property int _uidSeq: 0
    function _ensureUids(n) {
        n.items.forEach(function (it) { if (!it.uid) it.uid = "u" + (++_uidSeq) })
    }

    function _refreshSections() {
        var uids = note === null ? [] : note.items.map(function (it) { return it.uid })
        if (JSON.stringify(uids) !== JSON.stringify(itemUids))
            itemUids = uids
        var open = [], done = []
        if (note !== null && note.type === "LIST")
            note.items.forEach(function (it, i) { (it.checked ? done : open).push(i) })
        if (JSON.stringify(open) !== JSON.stringify(openIndexes))
            openIndexes = open
        if (JSON.stringify(done) !== JSON.stringify(doneIndexes))
            doneIndexes = done
    }
    onNoteChanged: _refreshSections()

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
        _ensureUids(after)
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
        var copy = stored ? _clone(stored) : null
        if (copy)
            _ensureUids(copy)
        note = copy
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
