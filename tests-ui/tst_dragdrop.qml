import QtQuick
import QtTest
import "../package/contents/ui/viewmodel" as VM
import "../package/contents/ui/views" as V
import "../package/contents/code/providers/fake.js" as Fake

// UI test on the real screens with synthetic mouse events. It needs the Plasma/Kirigami QML modules,
// so it runs on a Plasma machine (scripts/test-ui.sh), not in the build container.
Item {
    id: win
    width: 560
    height: 440

    readonly property var acc: ({ key: "fake:me", providerId: "fake", accountId: "me", displayName: "me", meta: {} })
    property var serverData: ({
        labels: [{ id: "L1", name: "Work" }, { id: "L2", name: "Home" }],
        notes: [
            { id: "n1", title: "Plain", text: "unsorted", order: 30 },
            { id: "n2", title: "Already", text: "has label", order: 20, labels: [{ id: "L1", name: "Work" }] },
            { id: "n3", title: "Third", text: "x", order: 10 }
        ]
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
    VM.NoteEditorViewModel { id: editor; notes: notes }

    V.NotesRoot { id: root; anchors.fill: parent; vm: notes; accountsVm: accounts; editor: editor }

    TestCase {
        name: "DragAndDrop"
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
            return find(root, function (i) { return i.note !== undefined && i.note && i.note.id === id && i.width > 100 })
        }
        function group(key) {
            var rail = find(root, function (i) { return i.hasOwnProperty("collapsed") && i.hasOwnProperty("multiAccount") })
            return find(rail, function (i) { return i.modelData !== undefined && i.modelData && i.modelData.key === key })
        }
        function drag(from, to) {
            var a = center(from), b = center(to)
            mousePress(win, a.x, a.y)
            mouseMove(win, a.x + 4, a.y + 4, 0, Qt.LeftButton)
            mouseMove(win, a.x + 20, a.y + 10, 0, Qt.LeftButton)
            mouseMove(win, (a.x + b.x) / 2, (a.y + b.y) / 2, 0, Qt.LeftButton)
            mouseMove(win, b.x, b.y, 0, Qt.LeftButton)
            mouseMove(win, b.x + 1, b.y, 0, Qt.LeftButton)
            mouseRelease(win, b.x, b.y)
        }

        function init() {
            tryVerify(function () { return notes.loaded && !notes.syncing })
            wait(700)   // let a screen transition finish before pressing
        }

        function test_clickOpensTheNote() {
            var c = card("n3")
            verify(c, "card n3")
            var p = center(c)
            mouseClick(win, p.x, p.y)
            tryVerify(function () { return notes.currentNoteKey === "fake:me/n3" })
            notes.closeNote()
        }

        function test_dragCardOntoLabelAddsIt() {
            var from = card("n1")
            var to = group("label:fake:me|L2")
            verify(from && to, "card and group found")
            drag(from, to)
            tryVerify(function () { return notes.noteByKey("fake:me/n1").labels.length === 1 })
            compare(notes.noteByKey("fake:me/n1").labels[0].id, "L2")
            compare(notes.lastAction.kind, "labeled")
            compare(notes.currentNoteKey, "")            // a drag is not a click
        }

        function test_dropOntoAGroupThatRefusesDoesNothing() {
            var before = notes.noteByKey("fake:me/n3").labels.length
            drag(card("n3"), group("all"))
            wait(100)
            compare(notes.noteByKey("fake:me/n3").labels.length, before)
        }
    }
}
