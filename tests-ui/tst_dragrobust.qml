import QtQuick
import QtTest
import "../package/contents/ui/viewmodel" as VM
import "../package/contents/ui/views" as V
import "../package/contents/code/providers/fake.js" as Fake

// Regression for the widget: the notes screen is created before it is attached to a window (as plasmashell
// does with the popup content). Dragging a card must not rearrange or hide the screen, and a drag must always
// end cleanly, whatever happens to the card.
Item {
    id: win
    width: 560
    height: 440

    readonly property var acc: ({ key: "fake:me", providerId: "fake", accountId: "me", displayName: "me", meta: {} })

    function makeNotes(count) {
        var notes = []
        for (var i = 0; i < count; i++)
            notes.push({ id: "n" + i, title: "Note " + i, text: "line one\nline two\nline three", order: 1000 - i })
        return notes
    }
    property var serverData: ({
        labels: [{ id: "L1", name: "Work" }, { id: "L2", name: "Home" }],
        notes: makeNotes(14)
    })

    QtObject {
        id: accounts
        property bool multiAccount: false
        property var sessions: [{
            account: win.acc,
            provider: { id: "fake", name: "Fake", icon: "knotes", capabilities: Object.assign({}, Fake.capabilities, { nestedItems: true }) },
            session: Fake.createSession(win.acc, "s", { data: win.serverData })
        }]
    }
    VM.NotesViewModel { id: notes; accounts: accounts; writeDelay: 50 }

    Item { id: host; anchors.fill: parent }
    Component { id: screenComp; V.NotesScreen {} }

    property var screen: null

    TestCase {
        name: "DragRobustness"
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
        function center(item) { return item.mapToItem(win, item.width / 2, item.height / 2) }
        function card(id) {
            return find(win.screen, function (i) { return i.note !== undefined && i.note && i.note.id === id && i.width > 100 })
        }
        function rail() {
            return find(win.screen, function (i) { return i.hasOwnProperty("collapsed") && i.hasOwnProperty("multiAccount") })
        }
        function group(key) {
            return find(rail(), function (i) { return i.modelData !== undefined && i.modelData && i.modelData.key === key })
        }
        function list() {
            return find(win.screen, function (i) { return i.hasOwnProperty("contentY") && i.hasOwnProperty("count") })
        }
        // The drag layer (DragLayer.qml): `active` while a note is being dragged.
        function dragLayer() {
            return find(win.screen, function (i) { return i.hasOwnProperty("watchdogInterval") })
        }

        function initTestCase() {
            // Created with no parent and no window, attached afterwards.
            win.screen = screenComp.createObject(null, { vm: notes, accountsVm: accounts })
            win.screen.parent = host
            win.screen.width = host.width
            win.screen.height = host.height
            tryVerify(function () { return notes.loaded && !notes.syncing })
            wait(300)
        }

        function init() { wait(400) }

        function test_dragKeepsTheScreenIntactAndEndsCleanly() {
            var from = card("n1"), to = group("label:fake:me|L2")
            verify(from && to, "card and group found")
            var railWidth = rail().width, listHeight = list().height
            verify(railWidth > 20 && listHeight > 100)

            var a = center(from), b = center(to)
            mousePress(win, a.x, a.y)
            mouseMove(win, a.x - 6, a.y + 2, 0, Qt.LeftButton)
            mouseMove(win, a.x - 30, a.y + 10, 0, Qt.LeftButton)
            mouseMove(win, (a.x + b.x) / 2, (a.y + b.y) / 2, 0, Qt.LeftButton)
            mouseMove(win, b.x, b.y, 0, Qt.LeftButton)
            wait(50)

            // In the middle of the drag everything is still there.
            verify(dragLayer().active && dragLayer().visible, "drag layer shown while dragging")
            compare(rail().width, railWidth)
            verify(list().height > listHeight * 0.9, "list kept its height: " + list().height + " vs " + listHeight)
            verify(win.screen.width > 0 && win.screen.height > 0)

            mouseRelease(win, b.x, b.y)
            tryVerify(function () { return !dragLayer().active })
            verify(!dragLayer().visible, "drag layer hidden after the drop")
            compare(notes.noteByKey("fake:me/n1").labels.length, 1)
        }

        function test_dropOnNothingStillEndsTheDrag() {
            var from = card("n2")
            var a = center(from)
            mousePress(win, a.x, a.y)
            mouseMove(win, a.x - 8, a.y, 0, Qt.LeftButton)
            mouseMove(win, a.x - 40, a.y + 30, 0, Qt.LeftButton)
            wait(30)
            verify(dragLayer().active)
            mouseRelease(win, 5, 5)             // far away, over the toolbar
            tryVerify(function () { return !dragLayer().active })
            verify(!dragLayer().visible)
            verify(notes.currentNoteKey === "")
        }

        function test_aNewDragWorksAfterAnAbortedOne() {
            // First drag: ends over the toolbar, i.e. on nothing.
            var from = card("n0"), to = group("label:fake:me|L1")
            var a = center(from), b = center(to)
            mousePress(win, a.x, a.y)
            mouseMove(win, a.x - 8, a.y, 0, Qt.LeftButton)
            mouseMove(win, 20, 20, 0, Qt.LeftButton)
            mouseRelease(win, 20, 20)
            tryVerify(function () { return !dragLayer().active })
            compare(notes.noteByKey("fake:me/n0").labels.length, 0)
            wait(400)

            // Second drag works as usual (positions are measured again: layout may have changed).
            a = center(card("n0"))
            b = center(group("label:fake:me|L1"))
            mousePress(win, a.x, a.y)
            mouseMove(win, a.x - 8, a.y, 0, Qt.LeftButton)
            mouseMove(win, (a.x + b.x) / 2, (a.y + b.y) / 2, 0, Qt.LeftButton)
            mouseMove(win, b.x, b.y, 0, Qt.LeftButton)
            mouseMove(win, b.x + 1, b.y, 0, Qt.LeftButton)
            mouseRelease(win, b.x, b.y)
            tryVerify(function () { return notes.noteByKey("fake:me/n0").labels.length === 1 })
        }
    }
}
