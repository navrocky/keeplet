import QtQuick
import QtTest
import "../package/contents/code/providers/keep/nodes.js" as Nodes
import "../package/contents/code/providers/keep/mutations.js" as Mut

TestCase {
    name: "Mutations"

    readonly property string never: "1970-01-01T00:00:00.000000Z"
    readonly property string old: "2026-10-15T10:00:00.000000Z"
    property int counter: 0

    // Deterministic context: time moves forward, ids are predictable.
    function ctx() {
        var n = 0
        return {
            now: function () { n++; return "2026-10-16T00:00:0" + n + ".000000Z" },
            newId: function () { counter++; return "gen" + counter }
        }
    }

    function ts() { return { created: old, updated: old, trashed: never, deleted: never, userEdited: old } }
    function node(props) {
        var n = { kind: "notes#node", parentId: "root", timestamps: ts(), sortValue: "0" }
        for (var k in props) n[k] = props[k]
        return n
    }

    function stateWith() {
        var s = Nodes.createState()
        Nodes.applyChanges(s, {
            toVersion: "v1",
            userInfo: { labels: [{ mainId: "L1", name: "Work", timestamps: ts() }, { mainId: "L2", name: "Home", timestamps: ts() }] },
            nodes: [
                node({ id: "n1", serverId: "S-n1", type: "NOTE", title: "Shopping", color: "YELLOW", sortValue: "300",
                       labelIds: [{ labelId: "L1" }], baseNoteRevision: "r1" }),
                node({ id: "n1.b", serverId: "S-n1.b", parentId: "n1", type: "LIST_ITEM", text: "milk", sortValue: "100" }),
                node({ id: "l1", serverId: "S-l1", type: "LIST", title: "Todo", sortValue: "200" }),
                node({ id: "l1.a", parentId: "l1", type: "LIST_ITEM", text: "first", sortValue: "3000000" }),
                node({ id: "l1.b", parentId: "l1", type: "LIST_ITEM", text: "second", sortValue: "2000000" }),
                node({ id: "l1.c", parentId: "l1", type: "LIST_ITEM", text: "third", sortValue: "1000000" })
            ]
        })
        return s
    }

    function snap(state, id) { return Nodes.buildNote(state, id) }
    function ids(r) { return r.nodes.map(function (n) { return n.id }).join() }
    function byId(r, id) { return r.nodes.filter(function (n) { return n.id === id })[0] }

    // --- no-ops and field edits

    function test_unchangedSnapshotProducesNothing() {
        var s = stateWith()
        compare(Mut.commitNote(s, snap(s, "n1"), ctx()).nodes.length, 0)
        compare(Mut.commitNote(s, snap(s, "l1"), ctx()).nodes.length, 0)
    }

    function test_titleChangeTouchesNoteAndUserEdited() {
        var s = stateWith()
        var sn = snap(s, "n1")
        sn.title = "Groceries"
        var r = Mut.commitNote(s, sn, ctx())
        compare(ids(r), "n1")
        var n = byId(r, "n1")
        compare(n.title, "Groceries")
        compare(n.serverId, "S-n1")                 // server fields survive
        compare(n.baseNoteRevision, "r1")
        verify(n.timestamps.updated !== old)
        verify(n.timestamps.userEdited !== old)
        compare(s.nodes.n1.title, "Shopping")       // the state itself is not touched by commitNote
    }

    function test_colorPinArchiveDoNotBumpUserEdited() {
        var s = stateWith()
        var sn = snap(s, "n1")
        sn.color = "BLUE"; sn.pinned = true; sn.archived = true
        var n = byId(Mut.commitNote(s, sn, ctx()), "n1")
        compare(n.color, "BLUE")
        compare(n.isPinned, true)
        compare(n.isArchived, true)
        compare(n.timestamps.userEdited, old)
        verify(n.timestamps.updated !== old)
    }

    function test_trashAndRestore() {
        var s = stateWith()
        var sn = snap(s, "n1")
        sn.trashed = true
        var n = byId(Mut.commitNote(s, sn, ctx()), "n1")
        verify(Nodes.isSet(n.timestamps.trashed))
        // restore
        s.nodes.n1 = n
        sn = snap(s, "n1")
        verify(sn.trashed)
        sn.trashed = false
        n = byId(Mut.commitNote(s, sn, ctx()), "n1")
        verify(!Nodes.isSet(n.timestamps.trashed))
    }

    // --- body text

    function test_bodyTextChangeEditsBodyItemAndTouchesNote() {
        var s = stateWith()
        var sn = snap(s, "n1")
        sn.text = "milk, eggs"
        var r = Mut.commitNote(s, sn, ctx())
        compare(ids(r), "n1,n1.b")
        compare(byId(r, "n1.b").text, "milk, eggs")
        compare(byId(r, "n1.b").serverId, "S-n1.b")
        verify(byId(r, "n1").timestamps.userEdited !== old)
    }

    function test_noteWithoutBodyGetsOneWhenTextAppears() {
        var s = stateWith()
        delete s.nodes["n1.b"]
        var sn = snap(s, "n1")
        compare(sn.text, "")
        sn.text = "now with text"
        var r = Mut.commitNote(s, sn, ctx())
        var item = r.nodes.filter(function (n) { return n.type === "LIST_ITEM" })[0]
        compare(item.parentId, "n1")
        compare(item.text, "now with text")
    }

    // --- labels

    function test_addAndRemoveLabels() {
        var s = stateWith()
        var sn = snap(s, "n1")
        sn.labels = [{ id: "L2", name: "Home" }]        // L1 removed, L2 added
        var n = byId(Mut.commitNote(s, sn, ctx()), "n1")
        var l1 = n.labelIds.filter(function (l) { return l.labelId === "L1" })[0]
        var l2 = n.labelIds.filter(function (l) { return l.labelId === "L2" })[0]
        verify(Nodes.isSet(l1.deleted))                // marked deleted, not dropped
        verify(!Nodes.isSet(l2.deleted))
        compare(n.timestamps.userEdited, old)
    }

    function test_removedLabelEntryIsNotTreatedAsPresent() {
        var s = stateWith()
        s.nodes.n1.labelIds = [{ labelId: "L1", deleted: "2026-01-01T00:00:00.000000Z" }]
        var sn = snap(s, "n1")
        compare(sn.labels.length, 0)
        sn.labels = [{ id: "L1", name: "Work" }]       // re-adding a removed label
        var n = byId(Mut.commitNote(s, sn, ctx()), "n1")
        verify(n.labelIds.some(function (l) { return l.labelId === "L1" && !Nodes.isSet(l.deleted) }))
    }

    // --- checklists

    function test_checkItem() {
        var s = stateWith()
        var sn = snap(s, "l1")
        sn.items[1].checked = true
        var r = Mut.commitNote(s, sn, ctx())
        compare(ids(r), "l1,l1.b")
        compare(byId(r, "l1.b").checked, true)
        compare(byId(r, "l1").timestamps.userEdited, old)   // checking is not a content edit
    }

    function test_editItemText() {
        var s = stateWith()
        var sn = snap(s, "l1")
        sn.items[0].text = "FIRST"
        var r = Mut.commitNote(s, sn, ctx())
        compare(byId(r, "l1.a").text, "FIRST")
        verify(byId(r, "l1").timestamps.userEdited !== old)
    }

    function test_appendItemGetsLowestSortAndFreshId() {
        var s = stateWith()
        var sn = snap(s, "l1")
        sn.items.push({ id: "", text: "fourth", checked: false, indent: 0 })
        var r = Mut.commitNote(s, sn, ctx())
        var added = r.nodes.filter(function (n) { return n.text === "fourth" })[0]
        verify(added.id.indexOf("gen") === 0)
        compare(added.parentId, "l1")
        compare(added.type, "LIST_ITEM")
        verify(Number(added.sortValue) < 1000000)       // below the old last item
        compare(added.checked, false)
    }

    function test_insertItemInTheMiddleSortsBetweenNeighbours() {
        var s = stateWith()
        var sn = snap(s, "l1")
        sn.items.splice(1, 0, { id: "", text: "between", checked: false, indent: 0 })
        var r = Mut.commitNote(s, sn, ctx())
        var added = r.nodes.filter(function (n) { return n.text === "between" })[0]
        var v = Number(added.sortValue)
        verify(v < 3000000 && v > 2000000, "sort " + v)
    }

    function test_insertItemAtTopSortsAboveFirst() {
        var s = stateWith()
        var sn = snap(s, "l1")
        sn.items.unshift({ id: "", text: "top", checked: false, indent: 0 })
        var r = Mut.commitNote(s, sn, ctx())
        var added = r.nodes.filter(function (n) { return n.text === "top" })[0]
        verify(Number(added.sortValue) > 3000000)
    }

    function test_removeItemDeletesIt() {
        var s = stateWith()
        var sn = snap(s, "l1")
        sn.items.splice(1, 1)
        var r = Mut.commitNote(s, sn, ctx())
        var gone = byId(r, "l1.b")
        verify(Nodes.isSet(gone.timestamps.deleted))
        compare(gone.text, "second")
    }

    function test_indentAndOutdent() {
        var s = stateWith()
        var sn = snap(s, "l1")
        sn.items[1].indent = 1                          // "second" under "first"
        var r = Mut.commitNote(s, sn, ctx())
        compare(byId(r, "l1.b").superListItemId, "l1.a")

        s.nodes["l1.b"] = byId(r, "l1.b")
        s.nodes["l1.b"].superListItemServerId = "S-first"
        sn = snap(s, "l1")
        compare(sn.items[1].indent, 1)
        sn.items[1].indent = 0
        r = Mut.commitNote(s, sn, ctx())
        var back = byId(r, "l1.b")
        verify(back.superListItemId === undefined)
        verify(back.superListItemServerId === undefined)
    }

    // --- creation and deletion

    function test_createTextNote() {
        var s = stateWith()
        var r = Mut.commitNote(s, { id: "", type: "NOTE", title: "New", text: "body", color: "RED", pinned: true,
                                    archived: false, trashed: false, items: [], labels: [{ id: "L1", name: "Work" }] }, ctx())
        var top = r.nodes[0]
        compare(top.type, "NOTE")
        compare(top.parentId, "root")
        compare(top.title, "New")
        compare(top.color, "RED")
        compare(top.isPinned, true)
        compare(top.labelIds[0].labelId, "L1")
        verify(Number(top.sortValue) > 300)             // above every existing note
        var body = r.nodes[1]
        compare(body.type, "LIST_ITEM")
        compare(body.parentId, top.id)
        compare(body.text, "body")
        compare(r.id, top.id)
    }

    function test_createListWithIndentedItems() {
        var s = Nodes.createState()
        var r = Mut.createNote(s, { id: "", type: "LIST", title: "L", items: [
            { id: "", text: "a", checked: false, indent: 0 },
            { id: "", text: "b", checked: true, indent: 1 },
            { id: "", text: "c", checked: false, indent: 0 }
        ] }, ctx())
        compare(r.nodes.length, 4)
        var items = r.nodes.slice(1)
        verify(Number(items[0].sortValue) > Number(items[1].sortValue))
        verify(Number(items[1].sortValue) > Number(items[2].sortValue))
        compare(items[1].superListItemId, items[0].id)
        verify(items[2].superListItemId === undefined)
        compare(items[1].checked, true)
    }

    function test_createdNoteRoundTripsThroughTheState() {
        var s = Nodes.createState()
        var id = Mut.commit(s, { id: "", type: "NOTE", title: "T", text: "x", color: "DEFAULT", pinned: false,
                                 archived: false, trashed: false, items: [], labels: [] }, ctx())
        var n = Nodes.buildNote(s, id)
        compare(n.title, "T")
        compare(n.text, "x")
        compare(Nodes.pendingCount(s), 2)               // note + body item
    }

    function test_deleteNoteRemovesNoteAndItems() {
        var s = stateWith()
        var nodes = Mut.deleteNote(s, "l1", ctx())
        compare(nodes.map(function (n) { return n.id }).sort().join(), "l1,l1.a,l1.b,l1.c")
        nodes.forEach(function (n) { verify(Nodes.isSet(n.timestamps.deleted)) })
    }

    function test_commitMarksDirtyAndHidesDeleted() {
        var s = stateWith()
        Mut.remove(s, "l1", ctx())
        compare(Nodes.pendingCount(s), 4)
        verify(Nodes.buildNotes(s).every(function (n) { return n.id !== "l1" }))
    }

    function test_commitIsIdempotentOnceApplied() {
        var s = stateWith()
        var sn = snap(s, "n1")
        sn.title = "Changed"
        Mut.commit(s, sn, ctx())
        compare(Mut.commitNote(s, snap(s, "n1"), ctx()).nodes.length, 0)
    }

    function test_itemWhoseNodeWasDeletedIsCreatedAgainWithAFreshId() {
        // Undo of "remove item": the snapshot still names the deleted item.
        var s = stateWith()
        var before = snap(s, "l1")
        var removed = JSON.parse(JSON.stringify(before))
        removed.items.splice(1, 1)
        Mut.commit(s, removed, ctx())                       // "second" is now deleted locally
        verify(Nodes.isDeleted(s.nodes["l1.b"]))

        var r = Mut.commitNote(s, before, ctx())             // undo: the old snapshot comes back
        var again = r.nodes.filter(function (n) { return n.text === "second" })[0]
        verify(again.id !== "l1.b")
        verify(!Nodes.isDeleted(again))
        compare(again.parentId, "l1")
        compare(r.nodes.filter(function (n) { return n.id === "l1.b" }).length, 0)   // the tombstone is left alone
    }
}
