import QtQuick
import QtTest
import "../package/contents/ui/viewmodel" as VM
import "../package/contents/code/providers/fake.js" as Fake
import "../package/contents/code/core/errors.js" as Errors

TestCase {
    id: tc
    name: "NotesViewModel"
    when: windowShown

    readonly property var keepAcc: ({ key: "fake:me@x", providerId: "fake", accountId: "me@x", displayName: "me@x", meta: {} })
    readonly property var workAcc: ({ key: "fake:work", providerId: "fake", accountId: "work", displayName: "work", meta: {} })

    function note(id, props) {
        var n = { id: id, title: id.toUpperCase(), order: 0, updated: "2026-01-01T00:00:00Z" }
        for (var k in props)
            n[k] = props[k]
        return n
    }

    function personalData() {
        return {
            labels: [{ id: "L1", name: "Work" }],
            notes: [
                note("a", { title: "Alpha", order: 30, updated: "2026-01-03T00:00:00Z", text: "apples" }),
                note("b", { title: "Beta", order: 20, pinned: true, labels: [{ id: "L1", name: "Work" }], text: "bananas" }),
                note("c", { title: "Gamma", order: 10, archived: true }),
                note("d", { title: "Delta", order: 5, trashed: true })
            ]
        }
    }

    function workData() {
        return {
            labels: [{ id: "L1", name: "Work" }],   // same id as in the personal account
            notes: [note("w1", { title: "Omega", order: 1, updated: "2026-02-01T00:00:00Z", labels: [{ id: "L1", name: "Work" }] })]
        }
    }

    Component { id: accountsComp; QtObject { property var sessions: [] } }
    Component {
        id: cacheComp
        QtObject {
            property var store: ({})
            property var removed: []
            function load(k) { return store[k] || "" }
            function save(k, v) { store[k] = v }
            function remove(k) { delete store[k]; removed.push(k) }
        }
    }
    Component { id: vmComp; VM.NotesViewModel {} }

    // opts: {data, fail} per account, like providers/fake.js createSession options.
    function entry(account, opts) {
        return { account: account, provider: Fake, session: Fake.createSession(account, "s", opts) }
    }

    function make(entries, withCache) {
        var accounts = accountsComp.createObject(tc, { sessions: entries })
        var cache = withCache === false ? null : cacheComp.createObject(tc)
        var vm = vmComp.createObject(tc, { accounts: accounts, cache: cache })
        return { vm: vm, accounts: accounts, cache: cache }
    }

    function ids(vm) { return vm.notes.map(function (n) { return n.id }).join() }

    // --- single account

    function test_initialSyncShowsNotesPinnedFirst() {
        var c = make([entry(keepAcc, { data: personalData() })])
        tryVerify(function () { return c.vm.loaded })
        compare(ids(c.vm), "b,a")   // pinned first, then provider order; archived and trashed hidden
        verify(!c.vm.syncing)
        verify(c.vm.lastSync !== null)
        compare(c.vm.error, "")
        compare(c.vm.labels.length, 1)
    }

    function test_viewSwitchesBetweenNotesArchiveTrash() {
        var c = make([entry(keepAcc, { data: personalData() })])
        tryVerify(function () { return c.vm.loaded })
        c.vm.view = "archive"
        compare(ids(c.vm), "c")
        c.vm.view = "trash"
        compare(ids(c.vm), "d")
        c.vm.view = "notes"
        compare(ids(c.vm), "b,a")
    }

    function test_searchMatchesTitleBodyAndLabel() {
        var c = make([entry(keepAcc, { data: personalData() })])
        tryVerify(function () { return c.vm.loaded })
        c.vm.searchText = "BANAN"
        compare(ids(c.vm), "b")
        c.vm.searchText = "alpha"
        compare(ids(c.vm), "a")
        c.vm.searchText = "work"
        compare(ids(c.vm), "b")
        c.vm.searchText = ""
        compare(ids(c.vm), "b,a")
    }

    function test_labelFilter() {
        var c = make([entry(keepAcc, { data: personalData() })])
        tryVerify(function () { return c.vm.loaded })
        c.vm.labelKey = "fake:me@x|L1"
        compare(ids(c.vm), "b")
    }

    function test_syncWritesCacheAndNextStartRestoresIt() {
        var c = make([entry(keepAcc, { data: personalData() })])
        tryVerify(function () { return c.vm.loaded })
        verify(c.cache.store["fake:me@x"].length > 0)

        // A second ViewModel starts from the cache even when the network is down.
        var offlineEntry = entry(keepAcc, { fail: new Errors.ProviderError("network") })
        var accounts2 = accountsComp.createObject(tc, { sessions: [offlineEntry] })
        var offline = vmComp.createObject(tc, { accounts: accounts2, cache: c.cache })
        verify(offline.loaded)
        compare(ids(offline), "b,a")
        tryVerify(function () { return offline.error === "network" })
        compare(ids(offline), "b,a")   // cached notes stay visible
    }

    function test_refreshPicksUpServerChanges() {
        var opts = { data: personalData() }
        var c = make([entry(keepAcc, opts)])
        tryVerify(function () { return c.vm.loaded && !c.vm.syncing })
        opts.data.notes.push(note("e", { title: "Epsilon", order: 40 }))
        c.vm.refresh()
        tryVerify(function () { return ids(c.vm) === "b,e,a" })
    }

    function test_errorKindsAreExposed() {
        var c = make([entry(keepAcc, { fail: new Errors.ProviderError("unauthorized") })])
        tryVerify(function () { return c.vm.error === "unauthorized" })
        verify(!c.vm.syncing)

        var d = make([entry(keepAcc, { fail: new Error("boom") })])
        tryVerify(function () { return d.vm.error === "failed" })
        verify(d.vm.errorDetail.indexOf("boom") >= 0)

        var e = make([entry(keepAcc, { fail: new Errors.ProviderError("auth", "BadAuthentication") })])
        tryVerify(function () { return e.vm.error === "auth" })
    }

    function test_removingAccountClearsNotesAndCache() {
        var c = make([entry(keepAcc, { data: personalData() })])
        tryVerify(function () { return c.vm.loaded })
        c.accounts.sessions = []
        compare(c.vm.notes.length, 0)
        verify(!c.vm.loaded)
        compare(c.cache.removed.join(), "fake:me@x")
    }

    function test_noSyncWithoutSessions() {
        var c = make([])
        c.vm.refresh()
        wait(30)
        verify(!c.vm.syncing)
        compare(c.vm.notes.length, 0)
    }

    function test_workWithoutCache() {
        var c = make([entry(keepAcc, { data: personalData() })], false)
        tryVerify(function () { return c.vm.loaded })
        compare(ids(c.vm), "b,a")
    }

    // --- several accounts

    function test_twoAccountsShareOneList() {
        var c = make([entry(keepAcc, { data: personalData() }), entry(workAcc, { data: workData() })])
        tryVerify(function () { return c.vm.notes.length === 3 })
        // Pinned first, then most recently updated across accounts: Omega (Feb) before Alpha (Jan 3).
        compare(ids(c.vm), "b,w1,a")
        compare(c.vm.notes[1].accountKey, "fake:work")
    }

    function test_accountFilterShowsOneAccountInItsOwnOrder() {
        var c = make([entry(keepAcc, { data: personalData() }), entry(workAcc, { data: workData() })])
        tryVerify(function () { return c.vm.notes.length === 3 })
        c.vm.accountFilter = "fake:work"
        compare(ids(c.vm), "w1")
        c.vm.accountFilter = "fake:me@x"
        compare(ids(c.vm), "b,a")
        c.vm.accountFilter = ""
        compare(c.vm.notes.length, 3)
    }

    function test_sameLabelIdInTwoAccountsIsKeptApart() {
        var c = make([entry(keepAcc, { data: personalData() }), entry(workAcc, { data: workData() })])
        tryVerify(function () { return c.vm.notes.length === 3 })
        compare(c.vm.labels.length, 2)
        c.vm.labelKey = "fake:work|L1"
        compare(ids(c.vm), "w1")
        c.vm.labelKey = "fake:me@x|L1"
        compare(ids(c.vm), "b")
    }

    function test_oneAccountFailingDoesNotHideTheOther() {
        var c = make([
            entry(keepAcc, { data: personalData() }),
            entry(workAcc, { fail: new Errors.ProviderError("network") })
        ])
        tryVerify(function () { return c.vm.errors.length === 1 && !c.vm.syncing })
        compare(ids(c.vm), "b,a")
        compare(c.vm.errors[0].accountKey, "fake:work")
        compare(c.vm.errors[0].kind, "network")
        compare(c.vm.errors[0].displayName, "work")
    }

    function test_addingAnAccountKeepsExistingState() {
        var c = make([entry(keepAcc, { data: personalData() })])
        tryVerify(function () { return c.vm.loaded && !c.vm.syncing })
        var existing = c.accounts.sessions[0]
        c.accounts.sessions = [existing, entry(workAcc, { data: workData() })]
        tryVerify(function () { return c.vm.notes.length === 3 })
        compare(c.cache.removed.length, 0)
    }
}
