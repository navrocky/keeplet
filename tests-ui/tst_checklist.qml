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
            wait(150)
            list().doneExpanded = true
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
            tryCompare(l, "contentHeight", l.openHeight + l.rowHeight + l.doneHeight)   // settled
            var full = l.contentHeight
            l.doneExpanded = false
            tryVerify(function () { return l.contentHeight < full })
            tryCompare(l, "contentHeight", l.openHeight + l.rowHeight)
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

        function fieldOf(index) { return find(rowOf(index), function (i) { return i.hasOwnProperty("cursorPosition") && i.hasOwnProperty("wrapMode") }) }
        function focusOn(index, pos) {
            var f = fieldOf(index)
            f.forceActiveFocus()
            f.cursorPosition = pos
            verify(f.activeFocus)
            return f
        }

        function test_enterAtTheEndAddsAnItemBelowAndFocusesIt() {
            var f = focusOn(0, 1)                                  // "a|"
            keyClick(Qt.Key_Return)
            compare(texts(), "a,,b,c,d")
            tryVerify(function () { return fieldOf(1).activeFocus })
        }

        function test_enterAtTheStartAddsAnItemAboveAndFocusesIt() {
            focusOn(2, 0)                                          // "|c"
            keyClick(Qt.Key_Return)
            compare(texts(), "a,b,,c,d")
            tryVerify(function () { return fieldOf(2).activeFocus })
            compare(fieldOf(2).text, "")
        }

        function test_enterInTheMiddleAndShiftEnterBreakTheLine() {
            editor.setItemText(0, "abcd")
            var f = focusOn(0, 2)
            keyClick(Qt.Key_Return)
            compare(texts(), "ab\ncd,b,c,d")                     // no new item
            f = focusOn(0, 5)                                      // at the very end
            keyClick(Qt.Key_Return, Qt.ShiftModifier)
            compare(editor.note.items[0].text, "ab\ncd\n")        // Shift+Enter breaks even at the end
            compare(editor.note.items.length, 4)
        }

        function test_backspaceOnAnEmptyItemRemovesItAndGoesToTheEndOfThePrevious() {
            editor.setItemText(2, "")
            focusOn(2, 0)
            keyClick(Qt.Key_Backspace)
            compare(texts(), "a,b,d")
            var prev = fieldOf(0)
            tryVerify(function () { return prev.activeFocus })
            compare(prev.cursorPosition, prev.length)
        }

        function test_backspaceOnTheEmptyFirstItemGoesToTheStartOfTheNext() {
            editor.setItemText(0, "")
            focusOn(0, 0)
            keyClick(Qt.Key_Backspace)
            compare(texts(), "b,c,d")
            tryVerify(function () { return fieldOf(1).activeFocus })        // "c" is now the first open item... index 1
            compare(fieldOf(1).cursorPosition, 0)
        }

        function test_cursorGoingDownIntoFoldedDoneUnfoldsIt() {
            var l = list()
            l.doneExpanded = false
            tryCompare(rowOf(1), "visible", false)
            focusOn(2, 1)                                        // last open item "c", cursor at the end
            keyClick(Qt.Key_Down)
            verify(l.doneExpanded)
            tryVerify(function () { return fieldOf(1).activeFocus })
        }

        function test_arrowsLeaveTheItemOnlyAtItsFirstAndLastLine() {
            editor.setItemText(0, "one\ntwo")
            var f = focusOn(0, 5)                                  // on the second line
            keyClick(Qt.Key_Up)
            verify(f.activeFocus)                                  // moved inside the text
            compare(f.cursorPosition < 4, true)
            keyClick(Qt.Key_Up)                                    // first line: stays (no item above)
            verify(f.activeFocus)
            f.cursorPosition = f.length
            keyClick(Qt.Key_Down)                                  // last line: the next open item (c)
            tryVerify(function () { return fieldOf(2).activeFocus })
        }

        function test_insertingAnItemKeepsTheOtherRowsAndSlidesThem() {
            var l = list()
            wait(200)
            var before = [rowOf(0), rowOf(1), rowOf(2), rowOf(3)]   // a, b, c, d
            var y = before[2].y                                     // c, an open item below a
            focusOn(0, 1)
            keyClick(Qt.Key_Return)                                 // new item below a
            compare(texts(), "a,,b,c,d")
            // The old items keep their delegates (no rebinding to other items): a, b, c, d are now items 0, 2, 3, 4.
            verify(rowOf(0) === before[0] && rowOf(2) === before[1] && rowOf(3) === before[2] && rowOf(4) === before[3])
            verify(before[2].y === y, "c has not jumped yet")       // it slides rather than jumps
            tryVerify(function () { return before[2].y > y })
            tryCompare(before[2], "y", l.rowHeight * 2)             // after the new open item
        }

        function test_removingAnItemDestroysOnlyItsRow() {
            var rowA = rowOf(0)
            var rowC = rowOf(2)
            editor.removeItem(1)                                    // b
            compare(texts(), "a,c,d")
            tryVerify(function () { return rowOf(3) === undefined })
            verify(rowOf(0) === rowA && rowOf(1) === rowC)
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
