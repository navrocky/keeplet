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
            property string labelMode: "multi"
            property var accountLabels: [{ id: "L1", name: "Work", accountKey: "acc" },
                                         { id: "L2", name: "Home", accountKey: "acc" }]
            function capabilities(accountKey) {
                return { colors: ["DEFAULT", "RED", "BLUE"], nestedItems: true, convertType: true, labels: labelMode }
            }
            function labelsOf(accountKey) {
                return accountLabels.filter(function (l) { return l.accountKey === accountKey })
            }
            property bool labelsEditable: true
            property int labelCounter: 0
            function canEditLabels(accountKey) { return labelsEditable }
            function labelNameError(accountKey, name) {
                var n = String(name).trim().toLowerCase()
                if (n === "")
                    return "empty"
                return labelsOf(accountKey).some(function (l) { return l.name.toLowerCase() === n }) ? "exists" : ""
            }
            function createLabel(accountKey, name) {
                if (labelNameError(accountKey, name) !== "")
                    return null
                labelCounter++
                var l = { id: "N" + labelCounter, name: String(name).trim(), accountKey: accountKey }
                accountLabels = accountLabels.concat([l])
                return { id: l.id, name: l.name, key: accountKey + "|" + l.id }
            }
            function writableAccounts() {
                return [{ key: "acc", name: "me" }, { key: "acc2", name: "work" }]
            }
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

    // --- labels and account of a new note

    function test_labelChoicesShowWhichAreOn() {
        var c = open(noteData({ labels: [{ id: "L2", name: "Home" }] }))
        compare(c.editor.labelChoices.map(function (l) { return l.name + ":" + l.on }).join(), "Home:true,Work:false")
    }

    function test_toggleLabelIsAnUndoableStep() {
        var c = open(noteData())
        c.editor.toggleLabel("L1")
        compare(c.editor.note.labels.map(function (l) { return l.id }).join(), "L1")
        c.editor.toggleLabel("L2")
        compare(c.editor.note.labels.map(function (l) { return l.id }).join(), "L1,L2")
        c.editor.toggleLabel("L1")
        compare(c.editor.note.labels.map(function (l) { return l.id }).join(), "L2")
        c.editor.undo()
        compare(c.editor.note.labels.map(function (l) { return l.id }).join(), "L1,L2")
        c.editor.flush()
        compare(c.notes.saved[0].labels.length, 2)
    }

    function test_singleCategoryProviderKeepsOneLabel() {
        var notes = notesComp.createObject(tc, { labelMode: "single" })
        var data = noteData({ labels: [{ id: "L1", name: "Work" }] })
        notes.store[data.key] = data
        var editor = editorComp.createObject(tc, { notes: notes, saveDelay: 20 })
        notes.currentNoteKey = data.key
        verify(editor.labelsSingle)
        editor.toggleLabel("L2")
        compare(editor.note.labels.map(function (l) { return l.id }).join(), "L2")
    }

    function test_noLabelsCapabilityMeansNoChoices() {
        var notes = notesComp.createObject(tc, { labelMode: "none" })
        var data = noteData()
        notes.store[data.key] = data
        var editor = editorComp.createObject(tc, { notes: notes })
        notes.currentNoteKey = data.key
        compare(editor.labelChoices.length, 0)
    }

    function test_unknownLabelIsIgnored() {
        var c = open(noteData())
        c.editor.toggleLabel("nope")
        verify(!c.editor.canUndo)
    }

    function test_newNoteMayChangeAccountUntilItIsStored() {
        var c = open(noteData({ id: "", key: "<new>", labels: [{ id: "L1", name: "Work" }] }))
        verify(c.editor.isNewUnsaved)
        compare(c.editor.accountChoices.length, 2)
        c.editor.setAccount("acc2")
        compare(c.editor.note.accountKey, "acc2")
        compare(c.editor.note.labels.length, 0)          // labels belong to the old account
        c.editor.undo()
        compare(c.editor.note.accountKey, "acc")
        compare(c.editor.note.labels.length, 1)
    }

    function test_storedNoteCannotChangeAccount() {
        var c = open(noteData())
        verify(!c.editor.isNewUnsaved)
        compare(c.editor.accountChoices.length, 0)
        c.editor.setAccount("acc2")
        compare(c.editor.note.accountKey, "acc")
    }

    // --- sections, order, conversion

    function items5() {
        return noteData({ id: "l", key: "acc/l", type: "LIST", text: "", items: [
            { id: "a", text: "a", checked: false, indent: 0 },
            { id: "b", text: "b", checked: true, indent: 0 },
            { id: "c", text: "c", checked: false, indent: 0 },
            { id: "c1", text: "c1", checked: false, indent: 1 },
            { id: "d", text: "d", checked: true, indent: 0 }
        ] })
    }
    function texts(editor) { return editor.note.items.map(function (i) { return i.text }).join() }

    function test_sectionsKeepItemOrder() {
        var c = open(items5())
        compare(c.editor.openIndexes.join(), "0,2,3")
        compare(c.editor.doneIndexes.join(), "1,4")
        c.editor.toggleItem(0)                       // first open item is done: it is first among done now
        compare(c.editor.doneIndexes.join(), "0,1,4")
        compare(texts(c.editor), "a,b,c,c1,d")       // the array itself does not change
    }

    function test_sectionsDoNotChangeWhileTyping() {
        var c = open(items5())
        var before = c.editor.openIndexes
        c.editor.setItemText(0, "abc")
        verify(c.editor.openIndexes === before)
    }

    function test_moveItemWithinSection() {
        var c = open(items5())
        c.editor.moveItemInSection(false, 0, 1)      // a goes after c (and its sub-item)
        compare(texts(c.editor), "b,c,c1,a,d")
        c.editor.moveItemInSection(false, 2, 0)      // a back above c
        compare(texts(c.editor), "b,a,c,c1,d")
        c.editor.undo()
        c.editor.undo()
        compare(texts(c.editor), "a,b,c,c1,d")
    }

    function test_movingAnItemWithSubitemsTakesThemAlong() {
        var c = open(items5())
        c.editor.moveItemInSection(false, 1, 0)      // c (+ c1) above a
        compare(texts(c.editor), "c,c1,a,b,d")
        compare(c.editor.note.items[1].indent, 1)
    }

    function test_clearDoneRemovesOnlyCheckedItems() {
        var c = open(items5())
        c.editor.clearDone()
        compare(texts(c.editor), "a,c,c1")
        verify(!c.editor.hasDone)
        c.editor.undo()
        compare(texts(c.editor), "a,b,c,c1,d")
    }

    function test_convertTextToListAndBack() {
        var c = open(noteData({ text: "milk\n\nbread" }))
        verify(c.editor.canConvert)
        c.editor.convertToList()
        compare(c.editor.note.type, "LIST")
        compare(texts(c.editor), "milk,bread")
        compare(c.editor.note.text, "")
        c.editor.toggleItem(0)
        c.editor.convertToText()
        compare(c.editor.note.type, "NOTE")
        compare(c.editor.note.text, "- [x] milk\n- [ ] bread")
        compare(c.editor.openIndexes.length, 0)
        c.editor.undo()
        compare(c.editor.note.type, "LIST")
    }

    function test_convertingKeepsCheckMarks() {
        var c = open(items5())
        c.editor.convertToText()
        compare(c.editor.note.text, "- [ ] a\n- [x] b\n- [ ] c\n  - [ ] c1\n- [x] d")
        c.editor.convertToList()
        compare(c.editor.note.items.map(function (i) { return (i.checked ? "x" : "-") + i.indent + i.text }).join(), "-0a,x0b,-0c,-1c1,x0d")
    }

    function test_listWithoutCheckMarksBecomesPlainText() {
        var c = open(listData())
        c.editor.convertToText()
        compare(c.editor.note.text, "one\ntwo")
    }

    function test_textWithMarkersBecomesAChecklist() {
        var c = open(noteData({ text: "[x] done\n[ ] open\n* [X] star\nplain" }))
        c.editor.convertToList()
        compare(c.editor.note.items.map(function (i) { return (i.checked ? "x" : "-") + i.text }).join(), "xdone,-open,xstar,-plain")
    }

    function test_asTextAlwaysHasMarkersForLists() {
        var c = open(listData())
        compare(c.editor.asText(), "Title\n\n- [ ] one\n- [ ] two")
        c = open(noteData())
        compare(c.editor.asText(), "Title\n\nBody")
    }

    function test_addItemAboveKeepsIndentAndAsksForFocus() {
        var c = open(items5())
        var focused = []
        c.editor.itemFocusRequested.connect(function (i) { focused.push(i) })
        c.editor.addItemAbove(3)                      // above c1 (indent 1)
        compare(texts(c.editor), "a,b,c,,c1,d")
        compare(c.editor.note.items[3].indent, 1)
        compare(focused.join(), "3")
        c.editor.undo()
        compare(texts(c.editor), "a,b,c,c1,d")
    }

    function test_itemsKeepTheirUidAcrossEditsAndUndo() {
        var c = open(items5())
        var uids = c.editor.itemUids.slice()
        compare(uids.length, 5)
        compare(new Set(uids).size, 5)
        c.editor.setItemText(0, "typing")
        compare(c.editor.itemUids.join(), uids.join())         // typing does not touch the sequence
        c.editor.addItem(0)
        compare(c.editor.itemUids.length, 6)
        compare(c.editor.itemUids[0], uids[0])
        compare(c.editor.itemUids[2], uids[1])                  // the others kept theirs
        c.editor.removeItem(0)
        c.editor.undo()                                         // the removed item is back with its own uid
        compare(c.editor.itemUids[0], uids[0])
        compare(c.editor.itemIndexOf(uids[3]), 4)
    }

    // --- creating a label from the editor

    function test_createLabelAssignsItAsOneUndoStep() {
        var c = open(noteData({ labels: [{ id: "L1", name: "Work" }] }))
        verify(c.editor.canCreateLabel)
        compare(c.editor.createLabel("  Ideas "), "")
        compare(c.editor.note.labels.map(function (l) { return l.name }).join(), "Work,Ideas")
        compare(c.notes.accountLabels.length, 3)
        c.editor.undo()
        compare(c.editor.note.labels.map(function (l) { return l.name }).join(), "Work")
        compare(c.notes.accountLabels.length, 3)   // the label itself stays
    }

    function test_createLabelRejectsBadNamesAndUnsupportedAccounts() {
        var c = open(noteData())
        compare(c.editor.createLabel(" "), "empty")
        compare(c.editor.createLabel("work"), "exists")
        compare(c.editor.labelNameError("Fresh"), "")
        compare(c.editor.note.labels.length, 0)
        c.notes.labelsEditable = false
        verify(!c.editor.canCreateLabel)
        compare(c.editor.createLabel("Fresh"), "unsupported")
    }

    function test_createLabelInSingleModeReplacesTheLabel() {
        var notes = notesComp.createObject(tc, { labelMode: "single" })
        var data = noteData({ labels: [{ id: "L1", name: "Work" }] })
        notes.store[data.key] = data
        var editor = editorComp.createObject(tc, { notes: notes, saveDelay: 20 })
        notes.currentNoteKey = data.key
        compare(editor.createLabel("Ideas"), "")
        compare(editor.note.labels.map(function (l) { return l.name }).join(), "Ideas")
    }
}
