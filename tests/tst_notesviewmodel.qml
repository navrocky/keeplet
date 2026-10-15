import QtQuick
import QtTest
import "../package/contents/ui/viewmodel" as VM

TestCase {
    id: tc
    name: "NotesViewModel"
    when: windowShown

    readonly property string never: "1970-01-01T00:00:00.000000Z"
    readonly property string now: "2026-10-15T10:00:00.000000Z"

    function ts() { return { created: now, updated: now, trashed: never, deleted: never } }
    function node(props) {
        var n = { kind: "notes#node", parentId: "root", timestamps: ts(), sortValue: "0" }
        for (var k in props)
            n[k] = props[k]
        return n
    }
    function response() {
        var trashedTs = ts()
        trashedTs.trashed = now
        return {
            toVersion: "v1", truncated: false,
            userInfo: { labels: [{ mainId: "L1", name: "Work", timestamps: ts() }] },
            nodes: [
                node({ id: "a", type: "NOTE", title: "Alpha", sortValue: "30" }),
                node({ id: "a.b", parentId: "a", type: "LIST_ITEM", text: "apples" }),
                node({ id: "b", type: "NOTE", title: "Beta", sortValue: "20", isPinned: true,
                       labelIds: [{ labelId: "L1" }] }),
                node({ id: "b.b", parentId: "b", type: "LIST_ITEM", text: "bananas" }),
                node({ id: "c", type: "NOTE", title: "Gamma", sortValue: "10", isArchived: true }),
                node({ id: "d", type: "NOTE", title: "Delta", sortValue: "5", timestamps: trashedTs })
            ]
        }
    }

    Component {
        id: authComp
        QtObject {
            property bool signedIn: true
            property string email: "me@example.com"
            property int tokenCalls: 0
            property int invalidated: 0
            function token() { tokenCalls++; return Promise.resolve("tok") }
            function invalidateToken() { invalidated++ }
        }
    }

    Component {
        id: cacheComp
        QtObject {
            property var store: ({})
            function load(k) { return store[k] || "" }
            function save(k, v) { store[k] = v }
            function remove(k) { delete store[k] }
        }
    }

    Component {
        id: vmComp
        VM.NotesViewModel {}
    }

    function make(overrides, transport) {
        var auth = authComp.createObject(tc)
        var cache = cacheComp.createObject(tc)
        var calls = { n: 0, bodies: [] }
        var t = transport || function (token, body) {
            calls.n++
            calls.bodies.push(body)
            return Promise.resolve(response())
        }
        var vm = vmComp.createObject(tc, Object.assign({ auth: auth, cache: cache, transport: t }, overrides || {}))
        return { vm: vm, auth: auth, cache: cache, calls: calls }
    }

    function ids(vm) {
        return vm.notes.map(function (n) { return n.id }).join()
    }

    function test_initialSyncShowsNotesPinnedFirst() {
        var c = make()
        tryVerify(function () { return c.vm.loaded })
        compare(ids(c.vm), "b,a")   // pinned first, then by sortValue; archived and trashed hidden
        verify(!c.vm.syncing)
        verify(c.vm.lastSync !== null)
        compare(c.vm.error, "")
        compare(c.vm.labels.length, 1)
    }

    function test_viewSwitchesBetweenNotesArchiveTrash() {
        var c = make()
        tryVerify(function () { return c.vm.loaded })
        c.vm.view = "archive"
        compare(ids(c.vm), "c")
        c.vm.view = "trash"
        compare(ids(c.vm), "d")
        c.vm.view = "notes"
        compare(ids(c.vm), "b,a")
    }

    function test_searchMatchesTitleBodyAndLabel() {
        var c = make()
        tryVerify(function () { return c.vm.loaded })
        c.vm.searchText = "BANAN"
        compare(ids(c.vm), "b")
        c.vm.searchText = "alpha"
        compare(ids(c.vm), "a")
        c.vm.searchText = "work"       // label name
        compare(ids(c.vm), "b")
        c.vm.searchText = ""
        compare(ids(c.vm), "b,a")
    }

    function test_labelFilter() {
        var c = make()
        tryVerify(function () { return c.vm.loaded })
        c.vm.labelId = "L1"
        compare(ids(c.vm), "b")
    }

    function test_syncWritesCacheAndNextStartRestoresIt() {
        var c = make()
        tryVerify(function () { return c.vm.loaded })
        verify(c.cache.store["me@example.com"].length > 0)

        // A second ViewModel starts from the cache even when the network is down.
        var offline = vmComp.createObject(tc, {
            auth: authComp.createObject(tc), cache: c.cache,
            transport: function () { return Promise.reject({ kind: "Network" }) }
        })
        compare(ids(offline), "b,a")
        verify(offline.loaded)
        tryVerify(function () { return offline.error === "network" })
        compare(ids(offline), "b,a")   // cached notes stay visible
    }

    function test_refreshSendsLastVersion() {
        var c = make()
        tryVerify(function () { return c.vm.loaded })
        c.vm.refresh()
        tryVerify(function () { return c.calls.n === 2 })
        verify(c.calls.bodies[0].targetVersion === undefined)
        compare(c.calls.bodies[1].targetVersion, "v1")
    }

    function test_unauthorizedRefreshesTokenAndRetriesOnce() {
        var n = 0
        var c = make({}, function () {
            n++
            return n === 1 ? Promise.reject({ kind: "Unauthorized" }) : Promise.resolve(response())
        })
        tryVerify(function () { return c.vm.loaded })
        compare(c.auth.invalidated, 1)
        compare(c.auth.tokenCalls, 2)
        compare(c.vm.error, "")
    }

    function test_persistentUnauthorizedReportsError() {
        var c = make({}, function () { return Promise.reject({ kind: "Unauthorized" }) })
        tryVerify(function () { return c.vm.error === "unauthorized" })
        verify(!c.vm.syncing)
    }

    function test_unexpectedErrorGivesFailedWithDetail() {
        var c = make({}, function () { return Promise.reject(new Error("boom")) })
        tryVerify(function () { return c.vm.error === "failed" })
        verify(c.vm.errorDetail.indexOf("boom") >= 0)
    }

    function test_signOutClearsEverything() {
        var c = make()
        tryVerify(function () { return c.vm.loaded })
        c.auth.signedIn = false
        compare(c.vm.notes.length, 0)
        verify(!c.vm.loaded)
        verify(c.cache.store["me@example.com"] === undefined)
    }

    function test_noSyncWhenSignedOut() {
        var auth = authComp.createObject(tc, { signedIn: false })
        var n = 0
        var vm = vmComp.createObject(tc, { auth: auth, transport: function () { n++; return Promise.resolve(response()) } })
        vm.refresh()
        wait(50)
        compare(n, 0)
    }
}
