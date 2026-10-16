import QtQuick
import QtTest
import "../package/contents/ui/viewmodel" as VM
import "../package/contents/ui/views" as V

// The checklist in the editor: unchecked items, a collapsible Done section, items sliding between them,
// and reordering by the drag handle. Real NoteScreen with synthetic mouse events.
Item {
    id: win
    width: 480
    height: 520

    QtObject {
        id: notes
        property string currentNoteKey: "acc/l"
        property var store: ({ "acc/l": {
            id: "l", key: "acc/l", accountKey: "acc", type: "LIST", title: "T", text: "", color: "DEFAULT",
            pinned: false, archived: false, trashed: false, labels: [],
            items: [
                { id: "a", text: "a", checked: false, indent: 0 },
                { id: "b", text: "b", checked: true, indent: 0 },
                { id: "c", text: "c", checked: false, indent: 0 },
                { id: "d", text: "d", checked: true, indent: 0 }
            ] } })
        function noteByKey(k) { return store[k] || null }
        function canWrite() { return true }
        function capabilities() { return { colors: [], nestedItems: true, convertType: true, labels: "none" } }
        function labelsOf() { return [] }
        function writableAccounts() { return [] }
        function closeNote() { currentNoteKey = "" }
        function removeNote() { return true }
        function saveNote(n) { store[n.key] = JSON.parse(JSON.stringify(n)); return n.key }
    }
    VM.NoteEditorViewModel { id: editor; notes: notes; saveDelay: 20 }
    V.NoteScreen { id: screen; anchors.fill: parent; vm: notes; editor: editor }

    TestCase {
        name: "Checklist"
        when: windowShown

        function find(item, pred) {
            if (pred(item))
                return item
            var kids = item.children
            for (var i = 0; i < kids.length; i++) {
                var r = find(kids[i], pred)
                if (r)
                    return r
            }
            return null
        }
        function list() { return find(screen, function (i) { return i.hasOwnProperty("doneExpanded") }) }
        function rowOf(index) { return list().children.filter(function (c) { return c.hasOwnProperty("done") && c.index === index })[0] }
        function texts() { return editor.note.items.map(function (i) { return i.text }).join() }

        readonly property var fresh: [
            { id: "a", text: "a", checked: false, indent: 0 },
            { id: "b", text: "b", checked: true, indent: 0 },
            { id: "c", text: "c", checked: false, indent: 0 },
            { id: "d", text: "d", checked: true, indent: 0 }
        ]
        function init() {
            notes.currentNoteKey = ""
            var n = notes.store["acc/l"]
            n.items = JSON.parse(JSON.stringify(fresh))
            notes.currentNoteKey = "acc/l"
            wait(50)
            list().doneExpanded = true
            list().instant = false
        }

        function test_rowsAreInTheirSections() {
            var l = list()
            verify(l)
            tryCompare(rowOf(0), "y", 0)
            tryCompare(rowOf(2), "y", l.rowHeight)
            tryCompare(rowOf(1), "y", l.doneTop)
            tryCompare(rowOf(3), "y", l.doneTop + l.rowHeight)
        }

        function test_checkedItemSlidesDownAndKeepsItsPlace() {
            var l = list()
            editor.toggleItem(0)                       // a is done: first of the done items
            tryCompare(rowOf(0), "y", l.doneTop)
            tryCompare(rowOf(1), "y", l.doneTop + l.rowHeight)
            tryCompare(rowOf(2), "y", 0)
            editor.toggleItem(0)
            tryCompare(rowOf(0), "y", 0)
            tryCompare(rowOf(1), "y", l.doneTop)
        }

        function test_foldingTheDoneSectionAnimatesTheHeightAndHidesTheRows() {
            var l = list()
            var full = l.contentHeight
            l.doneExpanded = false
            tryVerify(function () { return l.contentHeight < full })
            tryCompare(l, "contentHeight", l.openCount * l.rowHeight + l.rowHeight)
            tryCompare(rowOf(1), "visible", false)
            l.doneExpanded = true
            tryCompare(l, "contentHeight", full)
            tryCompare(rowOf(1), "visible", true)
        }

        function test_multilineItemGrowsAndPushesTheNextRowDown() {
            var l = list()
            var one = l.rowHeight
            tryCompare(rowOf(0), "height", one)                 // a short item keeps the minimum height
            editor.setItemText(0, "first line\nsecond line\nthird line")
            tryVerify(function () { return rowOf(0).height > one * 1.5 })
            tryCompare(rowOf(2), "y", rowOf(0).height)          // the next open item follows the taller row
            tryCompare(rowOf(1), "y", l.doneTop)
            verify(l.doneTop > one * 2.5)
            editor.setItemText(0, "short")
            tryCompare(rowOf(0), "height", one)
        }

        function test_dragHandleReordersWithinTheSection() {
            var l = list()
            var handle = find(rowOf(0), function (i) { return i.source === "handle-sort" })
            verify(handle)
            var p = handle.mapToItem(win, handle.width / 2, handle.height / 2)
            mousePress(win, p.x, p.y)
            for (var s = 1; s <= 10; s++)
                mouseMove(win, p.x, p.y + s * l.rowHeight / 8)
            mouseRelease(win, p.x, p.y + 10 * l.rowHeight / 8)
            compare(texts(), "b,c,a,d")      // a went below c
        }
    }
}
