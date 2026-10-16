import QtQuick
import QtTest
import "../package/contents/ui/viewmodel" as VM
import "../package/contents/ui/views" as V
import "../package/contents/code/providers/keep/index.js" as Keep
import "../package/contents/code/providers/keep/nodes.js" as Nodes
import "../package/contents/code/providers/keep/mutations.js" as Mut
import "../package/contents/code/core/workspace.js" as Workspace

// Timing harness (not a test): where does adding / removing a checklist item spend its time?
// Run: scripts/test-ui.sh bench_checklist   (prints a table with console.log; asserts nothing).
Item {
    id: win
    width: 520
    height: 560

    readonly property int noteCount: 1500
    readonly property int listSize: 40
    readonly property var acc: ({ key: "keep:bench@x", providerId: "keep", accountId: "bench@x", displayName: "bench", meta: {} })

    function ts() { return { created: "2026-10-15T10:00:00.000000Z", updated: "2026-10-15T10:00:00.000000Z",
                             trashed: "1970-01-01T00:00:00.000000Z", deleted: "1970-01-01T00:00:00.000000Z", userEdited: "2026-10-15T10:00:00.000000Z" } }
    function node(props) {
        var n = { kind: "notes#node", parentId: "root", timestamps: ts(), sortValue: "0" }
        for (var k in props) n[k] = props[k]
        return n
    }
    function bigState(session) {
        var s = session.createState()
        var nodes = []
        for (var i = 0; i < noteCount; i++) {
            nodes.push(node({ id: "n" + i, type: i % 3 === 0 ? "LIST" : "NOTE", title: "Note " + i, sortValue: String(1e9 - i * 1000) }))
            for (var j = 0; j < 3; j++)
                nodes.push(node({ id: "n" + i + "." + j, parentId: "n" + i, type: "LIST_ITEM", text: "item " + j + " of note " + i,
                                  sortValue: String(1e6 - j * 1000), checked: j === 2 }))
        }
        nodes.push(node({ id: "big", type: "LIST", title: "Big list", sortValue: "2000000000" }))
        for (var q = 0; q < listSize; q++)
            nodes.push(node({ id: "big." + q, parentId: "big", type: "LIST_ITEM", text: "line number " + q, sortValue: String(1e8 - q * 1000), checked: q % 4 === 3 }))
        Nodes.applyChanges(s, { toVersion: "v1", userInfo: { labels: [] }, nodes: nodes })
        return s
    }

    property var realSession: Keep.createSession(acc, "secret", {})
    property var session: Object.assign({}, realSession, {
        sync: function (state) { return Promise.resolve(state) }
    })
    QtObject {
        id: accounts
        property bool multiAccount: false
        property var sessions: []
    }
    VM.NotesViewModel { id: notes; accounts: accounts; writeDelay: 100000; cacheDelay: 100000 }
    VM.NoteEditorViewModel { id: editor; notes: notes; saveDelay: 100000 }
    V.NoteScreen { id: screen; anchors.fill: parent; vm: notes; editor: editor }

    TestCase {
        name: "BenchChecklist"
        when: windowShown

        function ms(fn) { var t = Date.now(); fn(); return Date.now() - t }
        function frame() { return ms(function () { waitForRendering(win, 2000) }) }
        function row(label, ms, frameMs, flushMs) { console.log("BENCH", label, "| call", ms, "ms | next frame", frameMs, "ms | flush", flushMs, "ms") }

        function test_bench() {
            var state = win.bigState(win.realSession)
            var entry = { account: win.acc, provider: { id: "keep", name: "Keep", icon: "x", capabilities: Keep.capabilities }, session: win.session }
            // Seed the account state through the session the ViewModel will use.
            var t0 = Date.now()
            accounts.sessions = [entry]
            tryVerify(function () { return notes.loaded || notes.notes.length > 0 }, 20000)
            // Replace the state with the big one (no network involved).
            notes._accs[win.acc.key].state = state
            var rebuild = ms(function () { notes._rebuild() })
            console.log("BENCH setup: nodes", Object.keys(state.nodes).length, "| _rebuild", rebuild, "ms | notes in list", notes.notes.length)

            notes.openNote(win.acc.key + "/big")
            tryVerify(function () { return editor.isOpen })
            wait(300)

            var steps = [
                ["addItem (middle)", function () { editor.addItem(10) }],
                ["removeItem (middle)", function () { editor.removeItem(11) }],
                ["toggleItem", function () { editor.toggleItem(5) }],
                ["setItemText", function () { editor.setItemText(3, "typing a longer text here") }]
            ]
            steps.forEach(function (st) {
                wait(200)
                var call = ms(st[1])
                var fr = frame()
                var fl = ms(function () { editor.flush() })
                var fr2 = frame()
                row(st[0], call, fr, fl + " (+frame " + fr2 + ")")
            })
            // The ViewModel alone: the same command with the screen detached from the editor's data.
            screen.visible = false
            wait(100)
            console.log("BENCH view hidden: addItem", ms(function () { editor.addItem(10) }), "ms | removeItem", ms(function () { editor.removeItem(11) }), "ms")
            screen.visible = true
            wait(200)
            var commit = ms(function () { Mut.commit(state, JSON.parse(JSON.stringify(editor.note)), undefined) })
            console.log("BENCH commit alone:", commit, "ms")
            var built, annotated, merged
            console.log("BENCH rebuild parts: buildNotes", ms(function () { built = win.session.notes(state) }), "ms |",
                        "annotate", ms(function () { annotated = Workspace.annotate(win.acc, built, win.session.labels(state)) }), "ms |",
                        "merge", ms(function () { merged = Workspace.merge([annotated]) }), "ms |",
                        "_applyFilter", ms(function () { notes._applyFilter() }), "ms |",
                        "_buildRail", ms(function () { notes._buildRail() }), "ms |",
                        "_updateStatus", ms(function () { notes._updateStatus() }), "ms")
            console.log("BENCH total", Date.now() - t0, "ms")
        }
    }
}
