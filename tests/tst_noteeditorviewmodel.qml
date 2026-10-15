import QtQuick
import QtTest
import "../package/contents/ui/viewmodel" as VM

TestCase {
    id: tc
    name: "NoteEditorViewModel"
    when: windowShown

    // Stand-in for NotesViewModel: an in-memory store of notes.
    Component {
        id: notesComp
        QtObject {
            property string currentNoteKey: ""
            property var store: ({})
            property var saved: []        // snapshots passed to saveNote, in order
            property var removed: []
            property bool writable: true
            property int idCounter: 0

            function noteByKey(key) { return store[key] || null }
            function canWrite(accountKey) { return writable }
            function capabilities(accountKey) { return { colors: ["DEFAULT", "RED", "BLUE"], nestedItems: true } }
            function closeNote() { currentNoteKey = "" }
            function removeNote(note) { removed.push(note.key); delete store[note.key]; return true }
            function saveNote(note) {
                saved.push(JSON.parse(JSON.stringify(note)))
                var copy = JSON.parse(JSON.stringify(note))
                if (!copy.id) {
                    idCounter++
                    copy.id = "new" + idCounter
                    copy.key = copy.accountKey + "/" + copy.id
                }
                copy.items = copy.items.map(function (it, i) {
                    it.id = it.id || (copy.id + ".item" + i)
                    return it
                })
                store[copy.key] = copy
                return copy.key
            }
        }
    }
    Component { id: editorComp; VM.NoteEditorViewModel {} }

    function noteData(props) {
        var n = { id: "a", key: "acc/a", accountKey: "acc", type: "NOTE", title: "Title", text: "Body",
                  items: [], color: "DEFAULT", pinned: false, archived: false, trashed: false, labels: [] }
        for (var k in props)
            n[k] = props[k]
        return n
    }
    function listData() {
        return noteData({ id: "l", key: "acc/l", type: "LIST", text: "", items: [
            { id: "i1", text: "one", checked: false, indent: 0 },
            { id: "i2", text: "two", checked: false, indent: 0 }
        ] })
    }

    function open(data, overrides) {
        var notes = notesComp.createObject(tc)
        notes.store[data.key] = data
        var editor = editorComp.createObject(tc, Object.assign({ notes: notes, saveDelay: 20, coalesceWindow: 60000 }, overrides || {}))
        notes.currentNoteKey = data.key
        return { notes: notes, editor: editor }
    }

    // --- loading

    function test_opensAWorkingCopyOfTheNote() {
        var c = open(noteData())
        verify(c.editor.isOpen)
        compare(c.editor.note.title, "Title")
        verify(c.editor.editable)
        verify(!c.editor.canUndo)
        verify(!c.editor.canRedo)
        compare(c.editor.colors.length, 3)
        verify(c.editor.nestedItems)
        // It is a copy: editing does not touch the stored note.
        c.editor.setTitle("Changed")
        compare(c.notes.store["acc/a"].title, "Title")
    }

    function test_noNoteMeansClosedEditor() {
        var notes = notesComp.createObject(tc)
        var editor = editorComp.createObject(tc, { notes: notes })
        verify(!editor.isOpen)
        verify(!editor.editable)
        editor.setTitle("x")     // harmless
        verify(editor.note === null)
    }

    // --- editing and undo/redo

    function test_changesAreUndoneAndRedoneAsOneStepPerKind() {
        var c = open(noteData())
        var e = c.editor
        e.setText("B"); e.setText("Bo"); e.setText("Bod")      // typing: one step
        e.setColor("RED")
        e.togglePinned()
        compare(e.note.text, "Bod")
        verify(e.canUndo)
        e.undo()
        verify(!e.note.pinned)
        e.undo()
        compare(e.note.color, "DEFAULT")
        e.undo()
        compare(e.note.text, "Body")                            // the whole typing run at once
        verify(!e.canUndo)
        verify(e.canRedo)
        e.redo(); e.redo(); e.redo()
        compare(e.note.text, "Bod")
        compare(e.note.color, "RED")
        verify(e.note.pinned)
        verify(!e.canRedo)
    }

    function test_changingBackToTheSameValueIsNotAStep() {
        var c = open(noteData())
        c.editor.setTitle("Title")
        verify(!c.editor.canUndo)
        c.editor.setArchived(false)
        verify(!c.editor.canUndo)
    }

    function test_newChangeAfterUndoDropsRedo() {
        var c = open(noteData())
        c.editor.setColor("RED")
        c.editor.undo()
        verify(c.editor.canRedo)
        c.editor.setColor("BLUE")
        verify(!c.editor.canRedo)
    }

    function test_checklistEditing() {
        var c = open(listData())
        var e = c.editor
        e.toggleItem(0)
        verify(e.note.items[0].checked)
        e.setItemText(1, "TWO")
        compare(e.note.items[1].text, "TWO")
        e.addItem(1)
        compare(e.note.items.length, 3)
        compare(e.note.items[2].id, "")
        e.setItemIndent(2, 1)
        compare(e.note.items[2].indent, 1)
        e.removeItem(0)
        compare(e.note.items.length, 2)
        e.undo()                                                // removal
        compare(e.note.items.length, 3)
        e.undo()                                                // indent
        compare(e.note.items[2].indent, 0)
    }

    function test_addItemRequestsFocusOnTheNewItem() {
        var c = open(listData())
        var requested = []
        c.editor.itemFocusRequested.connect(function (i) { requested.push(i) })
        c.editor.addItem(0)
        compare(requested.join(), "1")
        c.editor.addItem(-1)                                    // at the top
        compare(requested.join(), "1,0")
        compare(c.editor.note.items[0].text, "")
    }

    function test_indentIsLimitedToOneLevel() {
        var c = open(listData())
        c.editor.setItemIndent(0, 5)
        compare(c.editor.note.items[0].indent, 1)
        c.editor.setItemIndent(0, -3)
        compare(c.editor.note.items[0].indent, 0)
    }

    // --- saving

    function test_autosavesAfterThePause() {
        var c = open(noteData())
        c.editor.setTitle("New title")
        compare(c.notes.saved.length, 0)                        // not immediately
        tryVerify(function () { return c.notes.saved.length === 1 })
        compare(c.notes.saved[0].title, "New title")
    }

    function test_burstOfEditsIsOneSave() {
        var c = open(noteData())
        c.editor.setTitle("a"); c.editor.setTitle("ab"); c.editor.setTitle("abc")
        tryVerify(function () { return c.notes.saved.length >= 1 })
        wait(80)
        compare(c.notes.saved.length, 1)
        compare(c.notes.saved[0].title, "abc")
    }

    function test_closeSavesAtOnceAndReturnsToTheList() {
        var c = open(noteData(), { saveDelay: 60000 })
        c.editor.setText("Unsaved text")
        c.editor.close()
        compare(c.notes.saved.length, 1)
        compare(c.notes.saved[0].text, "Unsaved text")
        compare(c.notes.currentNoteKey, "")
    }

    function test_undoIsSavedToo() {
        var c = open(noteData())
        c.editor.setColor("RED")
        tryVerify(function () { return c.notes.saved.length === 1 })
        c.editor.undo()
        tryVerify(function () { return c.notes.saved.length === 2 })
        compare(c.notes.saved[1].color, "DEFAULT")
    }

    function test_nothingIsSavedWithoutChanges() {
        var c = open(noteData())
        c.editor.close()
        compare(c.notes.saved.length, 0)
    }

    function test_idsOfNewItemsAreAdoptedWithoutAnUndoStep() {
        var c = open(listData())
        c.editor.addItem(1)
        c.editor.setItemText(2, "three")
        c.editor.flush()
        compare(c.editor.note.items[2].id, "l.item2")
        c.editor.undo()          // reverts the text typing run, not the id adoption
        compare(c.editor.note.items.length, 3)
        compare(c.editor.note.items[2].text, "")
    }

    function test_aNoteDeletedElsewhereIsNotRecreatedByTheEditor() {
        var c = open(noteData(), { saveDelay: 60000 })
        c.editor.setTitle("Edited")
        delete c.notes.store["acc/a"]                           // gone on the server
        c.editor.flush()
        compare(c.notes.saved.length, 0)
    }

    function test_switchingNotesSavesThePreviousOne() {
        var c = open(noteData(), { saveDelay: 60000 })
        c.notes.store["acc/b"] = noteData({ id: "b", key: "acc/b", title: "Other" })
        c.editor.setTitle("Edited a")
        c.notes.currentNoteKey = "acc/b"
        compare(c.notes.saved.length, 1)
        compare(c.notes.saved[0].id, "a")
        compare(c.editor.note.title, "Other")
        verify(!c.editor.canUndo)                               // history belongs to one open note
    }

    function test_closingResetsTheHistory() {
        var c = open(noteData())
        c.editor.setColor("RED")
        c.editor.close()
        c.notes.currentNoteKey = "acc/a"
        verify(!c.editor.canUndo)                               // the history is gone
        compare(c.editor.note.color, "RED")                     // the saved change is what reopens
    }

    // --- trash, restore, delete

    function test_trashSavesAndCloses() {
        var c = open(noteData())
        c.editor.trash()
        compare(c.notes.saved.length, 1)
        verify(c.notes.saved[0].trashed)
        compare(c.notes.currentNoteKey, "")
    }

    function test_trashedNoteIsViewOnlyUntilRestored() {
        var c = open(noteData({ trashed: true }))
        verify(c.editor.trashed)
        verify(!c.editor.editable)
        c.editor.setTitle("nope")
        compare(c.editor.note.title, "Title")
        c.editor.restore()
        verify(!c.editor.note.trashed)
        verify(c.editor.editable)
        compare(c.notes.saved.length, 1)
        verify(!c.notes.saved[0].trashed)
    }

    function test_deleteForeverRemovesAndCloses() {
        var c = open(noteData({ trashed: true }))
        c.editor.deleteForever()
        compare(c.notes.removed.join(), "acc/a")
        compare(c.notes.currentNoteKey, "")
        compare(c.notes.saved.length, 0)
    }

    function test_readOnlyProviderCannotBeEdited() {
        var notes = notesComp.createObject(tc, { writable: false })
        var data = noteData()
        notes.store[data.key] = data
        var editor = editorComp.createObject(tc, { notes: notes, saveDelay: 20 })
        notes.currentNoteKey = data.key
        verify(editor.isOpen)
        verify(!editor.editable)
        editor.setTitle("x")
        compare(editor.note.title, "Title")
        wait(60)
        compare(notes.saved.length, 0)
    }
}
