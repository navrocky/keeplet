import QtQuick
import QtTest
import "../package/contents/ui/viewmodel" as VM
import "../package/contents/ui/views" as V
import "../package/contents/code/providers/fake.js" as Fake

// UI test of label management in the rail (needs the real Plasma/Kirigami modules: scripts/test-ui.sh).
Item {
    id: win
    width: 560
    height: 440

    readonly property var acc: ({ key: "fake:me", providerId: "fake", accountId: "me", displayName: "me", meta: {} })
    property var serverData: ({
        labels: [{ id: "L1", name: "Work" }],
        notes: [{ id: "n1", title: "Plain", text: "x", order: 30, labels: [{ id: "L1", name: "Work" }] }]
    })

    QtObject {
        id: accounts
        property bool multiAccount: false
        property var sessions: [{
            account: win.acc,
            provider: { id: "fake", name: "Fake", icon: "knotes", capabilities: Fake.capabilities },
            session: Fake.createSession(win.acc, "s", { data: win.serverData })
        }]
    }
    VM.NotesViewModel { id: notes; accounts: accounts; writeDelay: 50 }
    VM.NoteEditorViewModel { id: editor; notes: notes }

    V.NotesRoot { id: root; anchors.fill: parent; vm: notes; accountsVm: accounts; editor: editor }

    TestCase {
        name: "Labels"
        when: windowShown

        function find(item, pred) {
            if (item && pred(item))
                return item
            if (!item || item.data === undefined)
                return null
            // `data` also holds popups and dialogs, which are not in `children`.
            var kids = item.data
            for (var i = 0; i < kids.length; i++) {
                var r = find(kids[i], pred)
                if (r)
                    return r
            }
            return null
        }
        // Screens are created from Components inside NotesRoot, where `x: x` would bind a property to itself.
        function test_screenGetsTheSharedPreviewAndAccounts() {
            var screen = find(root, function (i) { return i.hasOwnProperty("linkPreview") && i.hasOwnProperty("accountsVm") })
            verify(screen)
            verify(screen.linkPreview !== null && screen.linkPreview !== undefined)
            compare(screen.accountsVm, accounts)
        }

        function rail() {
            return find(root, function (i) { return i.hasOwnProperty("collapsed") && i.hasOwnProperty("multiAccount") })
        }
        function rowOf(pred) {
            return find(rail(), function (i) { return i.modelData !== undefined && i.modelData && pred(i.modelData) })
        }
        function dialog(title) {
            // The dialogs are items of the window overlay, not children of the screen.
            return find(win.Window.window.contentItem, function (i) { return i.hasOwnProperty("initialName") && i.title === title })
        }

        function init() {
            tryVerify(function () { return notes.loaded && !notes.syncing })
            wait(700)
        }

        function test_railOffersNewLabelAndCreatesIt() {
            var add = rowOf(function (m) { return m.type === "addLabel" })
            verify(add, "the New label row")
            mouseClick(add)
            var d = dialog("New label")
            verify(d, "name dialog")
            tryVerify(function () { return d.visible })
            verify(d.width > 100 && d.height > 100, "the card covers the widget")
            tryCompare(d, "error", "empty")
            d.check = function (n) { return notes.labelNameError("fake:me", n) }
            d.submitted("Ideas")   // what accepting the dialog emits
            tryVerify(function () { return notes.labels.some(function (l) { return l.name === "Ideas" }) })
            d.close()
        }

        function test_rightClickRenamesAndDeletesViaTheMenu() {
            var row = rowOf(function (m) { return m.kind === "label" && m.name === "Work" })
            verify(row, "Work row")
            verify(row.editable)
            // The menu items are native; drive the same handlers the items call.
            var r = rail()
            r._askName("rename", row.modelData)
            var d = dialog("Rename label")
            verify(d)
            tryVerify(function () { return d.visible })
            tryCompare(d, "error", "")           // keeping the own name is allowed (set once the dialog opened)
            d.submitted("Job")
            tryVerify(function () { return notes.labels.some(function (l) { return l.name === "Job" }) })
            d.close()

            row = rowOf(function (m) { return m.kind === "label" && m.name === "Job" })
            r._askDelete(row.modelData)
            compare(r._target.kind, "delete")
            notes.deleteLabel(r._target.labelKey)
            tryVerify(function () { return notes.labels.every(function (l) { return l.name !== "Job" }) })
            compare(notes.notes.length, 1)       // the note stays
        }
    }
}
