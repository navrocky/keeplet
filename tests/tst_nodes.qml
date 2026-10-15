import QtQuick
import QtTest
import "../package/contents/code/nodes.js" as Nodes

TestCase {
    name: "Nodes"

    readonly property string never: "1970-01-01T00:00:00.000000Z"
    readonly property string now: "2026-10-15T10:00:00.000000Z"

    function ts(extra) {
        var t = { created: now, updated: now, trashed: never, deleted: never }
        for (var k in extra)
            t[k] = extra[k]
        return t
    }

    function node(props) {
        var n = { kind: "notes#node", parentId: "root", timestamps: ts(), sortValue: "0" }
        for (var k in props)
            n[k] = props[k]
        return n
    }

    function sampleResponse() {
        return {
            toVersion: "v1",
            truncated: false,
            userInfo: { labels: [
                { mainId: "L1", name: "Work", timestamps: ts() },
                { mainId: "L2", name: "Home", timestamps: ts() }
            ] },
            nodes: [
                node({ id: "n1", type: "NOTE", title: "Shopping", color: "YELLOW", isPinned: true,
                       sortValue: "300", labelIds: [{ labelId: "L1" }, { labelId: "gone" }, { labelId: "L2", deleted: ts() }] }),
                node({ id: "n1.b", parentId: "n1", type: "LIST_ITEM", text: "milk, eggs", sortValue: "100" }),
                node({ id: "l1", type: "LIST", title: "Todo", sortValue: "200", isArchived: true }),
                node({ id: "l1.a", parentId: "l1", type: "LIST_ITEM", text: "first", sortValue: "10" }),
                node({ id: "l1.b", parentId: "l1", type: "LIST_ITEM", text: "second", checked: true, sortValue: "20" }),
                node({ id: "l1.c", parentId: "l1", type: "LIST_ITEM", text: "sub of first",
                       superListItemId: "l1.a", sortValue: "5" }),
                node({ id: "n2", type: "NOTE", title: "Old", sortValue: "100",
                       timestamps: ts({ trashed: now }), color: "NO_SUCH_COLOR" }),
                node({ id: "img", parentId: "n2", type: "BLOB", serverId: "srv-img",
                       blob: { type: "IMAGE", mimetype: "image/png" } })
            ]
        }
    }

    function test_applyChanges_storesVersionNodesAndLabels() {
        var s = Nodes.createState()
        Nodes.applyChanges(s, sampleResponse())
        compare(s.version, "v1")
        compare(Object.keys(s.nodes).length, 8)
        compare(s.labels.L1.name, "Work")
    }

    function test_applyChanges_removesDeleted() {
        var s = Nodes.createState()
        Nodes.applyChanges(s, sampleResponse())
        Nodes.applyChanges(s, {
            toVersion: "v2",
            nodes: [node({ id: "n2", type: "NOTE", timestamps: ts({ deleted: now }) })],
            userInfo: { labels: [{ mainId: "L2", name: "Home", timestamps: ts({ deleted: now }) }] }
        })
        compare(s.version, "v2")
        verify(s.nodes.n2 === undefined)
        verify(s.labels.L2 === undefined)
        verify(s.nodes.n1 !== undefined)
    }

    function test_applyChanges_keepsRawNode() {
        var s = Nodes.createState()
        var r = sampleResponse()
        r.nodes[0].someFutureField = { x: 1 }
        Nodes.applyChanges(s, r)
        compare(s.nodes.n1.someFutureField.x, 1)
    }

    function test_buildNotes_orderAndFlags() {
        var s = Nodes.createState()
        Nodes.applyChanges(s, sampleResponse())
        var notes = Nodes.buildNotes(s)
        compare(notes.length, 3)
        compare(notes[0].id, "n1")   // sortValue 300
        compare(notes[1].id, "l1")   // 200
        compare(notes[2].id, "n2")   // 100
        verify(notes[0].pinned)
        verify(notes[1].archived)
        verify(notes[2].trashed)
        compare(notes[0].color, "YELLOW")
        compare(notes[2].color, "DEFAULT")
    }

    function test_buildNotes_textNote() {
        var s = Nodes.createState()
        Nodes.applyChanges(s, sampleResponse())
        var n = Nodes.buildNotes(s)[0]
        compare(n.title, "Shopping")
        compare(n.text, "milk, eggs")
        compare(n.items.length, 0)
    }

    function test_buildNotes_listItemsOrderAndIndent() {
        var s = Nodes.createState()
        Nodes.applyChanges(s, sampleResponse())
        var list = Nodes.buildNotes(s)[1]
        compare(list.type, "LIST")
        // Descending sortValue: "second"(20), "first"(10), then first's sub-item.
        compare(list.items.map(function (i) { return i.text }).join("|"), "second|first|sub of first")
        compare(list.items.map(function (i) { return i.indent }).join(""), "001")
        verify(list.items[0].checked)
        verify(!list.items[1].checked)
    }

    function test_buildNotes_labelsSkipUnknownAndRemoved() {
        var s = Nodes.createState()
        Nodes.applyChanges(s, sampleResponse())
        var n = Nodes.buildNotes(s)[0]
        compare(n.labels.length, 1)
        compare(n.labels[0].name, "Work")
    }

    function test_buildNotes_images() {
        var s = Nodes.createState()
        Nodes.applyChanges(s, sampleResponse())
        var n = Nodes.buildNotes(s)[2]
        compare(n.images.length, 1)
        compare(n.images[0].serverId, "srv-img")
        compare(n.images[0].mimeType, "image/png")
    }

    function test_buildLabels_sortedByName() {
        var s = Nodes.createState()
        Nodes.applyChanges(s, sampleResponse())
        compare(Nodes.buildLabels(s).map(function (l) { return l.name }).join(), "Home,Work")
    }

    function test_isSet() {
        verify(!Nodes.isSet("1970-01-01T00:00:00.000000Z"))
        verify(!Nodes.isSet(undefined))
        verify(Nodes.isSet("2026-10-15T10:00:00.000000Z"))
    }
}
