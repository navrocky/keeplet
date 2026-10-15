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
            var c = find(win.screen, function (i) { return i.note !== undefined && i.note && i.note.id === id && i.width > 100 })
            return c
        }
        function rail() {
            return find(win.screen, function (i) { return i.hasOwnProperty("collapsed") && i.hasOwnProperty("multiAccount") })
        }
        function group(key) {
            return find(rail(), function (i) { return i.modelData !== undefined && i.modelData && i.modelData.key === key })
        }
        // The notes list: of the ListViews on the screen (groups rail, notes) the widest one.
        function list() {
            var best = null
            function visit(item) {
                if (item.hasOwnProperty("contentY") && item.hasOwnProperty("count") && item.hasOwnProperty("displaced")
                        && (best === null || item.width > best.width))
                    best = item
                for (var i = 0; i < item.children.length; i++)
                    visit(item.children[i])
            }
            visit(win.screen)
            return best
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

        function init() {
            // Every test starts from the same screen, whatever the previous one did.
            notes.closeNote()
            notes.dismissAction()
            notes.select("all")
            notes.railCollapsed = false
            var l = list()
            if (l)
                l.contentY = l.originY
            wait(500)
        }

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

        // --- effects

        function ghostItem() {
            return find(dragLayer(), function (i) { return i.hasOwnProperty("animate") && i.hasOwnProperty("border") })
        }
        // Starts carrying card `id` (a few pixels to the left are enough to pick it up).
        function pickUp(id) {
            var a = center(card(id))
            mousePress(win, a.x, a.y)
            mouseMove(win, a.x - 6, a.y, 0, Qt.LeftButton)
            mouseMove(win, a.x - 14, a.y + 2, 0, Qt.LeftButton)
            tryVerify(function () { return dragLayer().active })
            return a
        }
        function putDown(x, y) {
            mouseRelease(win, x, y)
            tryVerify(function () { return !dragLayer().active })
            wait(500)
        }

        function test_listScrollsWhenTheCardIsHeldAtTheEdges() {
            var l = list()
            verify(l.contentHeight > l.height * 1.5, "the list is taller than its view")
            l.contentY = l.originY
            var a = pickUp("n1")
            var top = l.mapToItem(win, 0, 0), x = top.x + l.width / 2

            mouseMove(win, x, top.y + l.height - 4, 0, Qt.LeftButton)      // bottom edge
            wait(700)
            var down = l.contentY
            verify(down > l.originY + 40, "scrolled down: " + down)

            mouseMove(win, x, top.y + 4, 0, Qt.LeftButton)                  // top edge
            wait(900)
            verify(l.contentY < down - 20, "scrolled back up: " + l.contentY + " from " + down)

            mouseMove(win, x, top.y + l.height / 2, 0, Qt.LeftButton)      // middle: stays
            wait(100)
            var still = l.contentY
            wait(300)
            compare(l.contentY, still)
            putDown(x, top.y + l.height / 2)
            l.contentY = l.originY
        }

        function test_listStopsAtTheEnds() {
            var l = list()
            l.contentY = l.originY
            var a = pickUp("n1")
            var top = l.mapToItem(win, 0, 0), x = top.x + l.width / 2
            mouseMove(win, x, top.y + 2, 0, Qt.LeftButton)                  // already at the top
            wait(300)
            verify(l.contentY >= l.originY - 0.5, "not above the first card")
            putDown(x, top.y + 2)
        }

        function test_groupsGrowAndOthersDimWhileCarrying() {
            var a = pickUp("n3")        // a note without labels, so every label group can take it
            var home = group("label:fake:me|L2"), all = group("all")
            verify(home.scale <= 1.001 && all.opacity > 0.99, "nothing changed before carrying over groups")
            tryVerify(function () { return home.scale > 1.01 }, 2000, "groups that can take the note grow")
            tryVerify(function () { return all.opacity < 0.7 }, 2000, "groups that refuse dim")

            var b = center(home)
            mouseMove(win, b.x, b.y, 0, Qt.LeftButton)
            mouseMove(win, b.x + 1, b.y, 0, Qt.LeftButton)
            tryVerify(function () { return home.scale > 1.07 }, 2000, "the hovered group grows more")
            putDown(5, 5)                                                    // not a drop on the group
            // The rail is rebuilt after a drop, so look the rows up again.
            tryVerify(function () {
                var h = group("label:fake:me|L2"), al = group("all")
                return h && al && h.scale < 1.001 && al.opacity > 0.99
            }, 2000, "back to normal")
        }

        function test_carriedCardsSlotClosesAndTheOthersSlideTogether() {
            var l = list()
            l.contentY = l.originY
            var before = card("n2").mapToItem(l.contentItem, 0, 0).y
            var cardHeight = card("n1").height
            var a = pickUp("n1")
            tryVerify(function () { return card("n2").mapToItem(l.contentItem, 0, 0).y < before - cardHeight * 0.8 },
                      2000, "n2 moved up into the closed slot")
            putDown(5, 5)
            tryVerify(function () { return Math.abs(card("n2").mapToItem(l.contentItem, 0, 0).y - before) < 2 },
                      2000, "n2 is back after the drop on nothing")
        }

        function test_ghostShrinksFromTheCardToAChip() {
            var cardWidth = card("n1").width
            var a = center(card("n1"))
            mousePress(win, a.x, a.y)
            mouseMove(win, a.x - 6, a.y, 0, Qt.LeftButton)
            mouseMove(win, a.x - 14, a.y + 2, 0, Qt.LeftButton)
            tryVerify(function () { return dragLayer().active })
            var g = ghostItem()
            verify(g, "ghost found")
            tryVerify(function () { return g.width < cardWidth * 0.8 }, 2000, "ghost became a chip")
            verify(g.width > 40)
            putDown(5, 5)
        }

        // --- manual order

        function idsInList() {
            return notes.notes.map(function (n) { return n.id }).join()
        }

        function test_aCardDroppedBetweenOthersTakesThatPlace() {
            verify(notes.reorderEnabled, "one account, no search: manual order is on")
            compare(idsInList().indexOf("n0,n1,n2,n3"), 0)
            var from = pickUp("n3")
            // Hold it just inside the top of n1: the gap opens in front of n1.
            var target = card("n1").mapToItem(win, card("n1").width / 2, 6)
            mouseMove(win, target.x, target.y, 0, Qt.LeftButton)
            mouseMove(win, target.x + 1, target.y + 1, 0, Qt.LeftButton)
            tryVerify(function () { return card("n1").parent.gap > 10 }, 2000, "a gap opens in front of n1")
            mouseRelease(win, target.x + 1, target.y + 1)
            tryVerify(function () { return !dragLayer().active })
            tryVerify(function () { return idsInList().indexOf("n0,n3,n1,n2") === 0 }, 2000, "order: " + idsInList())
            // The gap is gone again and the order is what the provider holds.
            tryVerify(function () { return card("n1").parent.gap < 1 }, 2000)
            var orders = notes.notes.slice(0, 5).map(function (n) { return n.order })
            for (var i = 1; i < orders.length; i++)
                verify(orders[i - 1] > orders[i], "descending: " + orders.join())
            verify(notes.undoLast())
            compare(idsInList().indexOf("n0,n1,n2,n3"), 0)
        }

        function test_theGapAtTheEndOfTheListOpensInTheFooter() {
            var l = list()
            var from = pickUp("n1")
            l.contentY = l.originY + Math.max(0, l.contentHeight - l.height)        // show the end
            wait(100)
            var top = l.mapToItem(win, 0, 0)
            mouseMove(win, top.x + l.width / 2, top.y + l.height - 3, 0, Qt.LeftButton)
            wait(1200)                                                              // autoscroll to the bottom
            verify(win.screen.insertBefore >= 0, "an insertion point exists near the bottom")
            putDown(5, 5)
            tryVerify(function () { return win.screen.insertBefore === -1 })
            l.contentY = l.originY
        }

        function test_noGapWhenSeveralAccountsAreMixed() {
            // Simulated by a search: the list is filtered, so positions are not meaningful.
            notes.searchText = "Note"
            verify(!notes.reorderEnabled)
            var from = pickUp("n1")
            var target = card("n3").mapToItem(win, card("n3").width / 2, 6)
            mouseMove(win, target.x, target.y, 0, Qt.LeftButton)
            wait(150)
            compare(win.screen.insertBefore, -1)
            putDown(target.x, target.y)
            notes.searchText = ""
        }
    }
}
