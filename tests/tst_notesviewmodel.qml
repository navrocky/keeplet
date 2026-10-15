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
        return {
            account: account,
            provider: { id: Fake.id, name: Fake.name, icon: Fake.icon, capabilities: Fake.capabilities },
            session: Fake.createSession(account, "s", opts)
        }
    }

    function make(entries, withCache) {
        var accounts = accountsComp.createObject(tc, { sessions: entries })
        var cache = withCache === false ? null : cacheComp.createObject(tc)
        var vm = vmComp.createObject(tc, { accounts: accounts, cache: cache, writeDelay: 20 })
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
        c.vm.select("archive")
        compare(ids(c.vm), "c")
        c.vm.select("trash")
        compare(ids(c.vm), "d")
        c.vm.select("all")
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
        c.vm.select("label:fake:me@x|L1")
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
        c.vm.select("label:fake:work|L1")
        compare(ids(c.vm), "w1")
        c.vm.select("label:fake:me@x|L1")
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

    // --- groups, rail and navigation (stage A)

    function railKeys(vm) {
        return vm.rail.map(function (i) { return i.type === "header" ? "#" + i.accountKey : i.key }).join()
    }
    function groupCount(vm, key) {
        var g = vm.rail.filter(function (i) { return i.key === key })[0]
        return g ? g.count : -1
    }

    function test_unlabeledGroupShowsNotesWithoutLabels() {
        var c = make([entry(keepAcc, { data: personalData() })])
        tryVerify(function () { return c.vm.loaded })
        c.vm.select("unlabeled")
        compare(ids(c.vm), "a")   // b has a label, c is archived, d is trashed
        c.vm.select("all")
        compare(ids(c.vm), "b,a")  // "all" stays the full, first group
    }

    function test_railSingleAccountIsFlat() {
        var c = make([entry(keepAcc, { data: personalData() })])
        tryVerify(function () { return c.vm.loaded })
        compare(railKeys(c.vm), "all,unlabeled,label:fake:me@x|L1,archive,trash")
        verify(c.vm.railVisible)
        compare(groupCount(c.vm, "all"), 2)
        compare(groupCount(c.vm, "unlabeled"), 1)
        compare(groupCount(c.vm, "label:fake:me@x|L1"), 1)
        compare(groupCount(c.vm, "archive"), 1)
        compare(groupCount(c.vm, "trash"), 1)
        compare(c.vm.rail[0].kind, "all")
        compare(c.vm.rail[2].name, "Work")
        verify(c.vm.rail[1].droppable && c.vm.rail[2].droppable && !c.vm.rail[0].droppable)
    }

    function test_railMultiAccountGroupsLabelsUnderAccountHeaders() {
        var c = make([entry(keepAcc, { data: personalData() }), entry(workAcc, { data: workData() })])
        tryVerify(function () { return c.vm.notes.length === 3 })
        compare(railKeys(c.vm), "all,unlabeled,#fake:me@x,label:fake:me@x|L1,#fake:work,label:fake:work|L1,archive,trash")
        compare(c.vm.rail[2].name, "me@x")
        // Counts follow the account scope.
        c.vm.selectAccount("fake:work")
        compare(railKeys(c.vm), "all,unlabeled,label:fake:work|L1,archive,trash")
        compare(groupCount(c.vm, "all"), 1)
        c.vm.selectAccount("")
        compare(groupCount(c.vm, "all"), 3)
    }

    function test_accountTabsListAllPlusAccounts() {
        var c = make([entry(keepAcc, { data: personalData() }), entry(workAcc, { data: workData() })])
        tryVerify(function () { return c.vm.notes.length === 3 })
        compare(c.vm.accountTabs.map(function (t) { return t.key }).join(), ",fake:me@x,fake:work")
        compare(c.vm.accountTabs[2].name, "work")
    }

    function test_selectionFallsBackWhenLabelDisappears() {
        var opts = { data: personalData() }
        var c = make([entry(keepAcc, opts)])
        tryVerify(function () { return c.vm.loaded && !c.vm.syncing })
        c.vm.select("label:fake:me@x|L1")
        compare(ids(c.vm), "b")
        opts.data.labels = []
        opts.data.notes[1].labels = []
        c.vm.refresh()
        tryVerify(function () { return c.vm.selected === "all" })
        compare(ids(c.vm), "b,a")
    }

    function test_railHiddenWhenProviderHasNothingToGroup() {
        // Only "all" would remain: no labels, no archive, no trash.
        var bare = { account: keepAcc, provider: {
            capabilities: { labels: "none", archive: false, trash: false },
            icon: "x"
        }, session: Fake.createSession(keepAcc, "s", { data: { notes: [note("z")], labels: [] } }) }
        var c = make([bare])
        tryVerify(function () { return c.vm.loaded })
        verify(!c.vm.railVisible)
        compare(c.vm.rail.length, 1)
    }

    function test_openNoteTracksTheNoteAndClosesWhenItDisappears() {
        var opts = { data: personalData() }
        var c = make([entry(keepAcc, opts)])
        tryVerify(function () { return c.vm.loaded && !c.vm.syncing })
        c.vm.openNote("fake:me@x/a")
        compare(c.vm.currentNote.title, "Alpha")
        // Fresh data replaces the open note.
        opts.data.notes[0].title = "Alpha 2"
        c.vm.refresh()
        tryVerify(function () { return c.vm.currentNote && c.vm.currentNote.title === "Alpha 2" })
        // Opening works regardless of the selected group or search.
        c.vm.searchText = "nomatch"
        compare(c.vm.currentNote.title, "Alpha 2")
        c.vm.searchText = ""
        // The note vanished on the server.
        opts.data.notes.splice(0, 1)
        c.vm.refresh()
        tryVerify(function () { return c.vm.currentNoteKey === "" })
        verify(c.vm.currentNote === null)
    }

    function test_closeNote() {
        var c = make([entry(keepAcc, { data: personalData() })])
        tryVerify(function () { return c.vm.loaded })
        c.vm.openNote("fake:me@x/b")
        verify(c.vm.currentNote !== null)
        c.vm.closeNote()
        compare(c.vm.currentNoteKey, "")
        verify(c.vm.currentNote === null)
    }

    // --- writing (stage C)

    function first(vm, id) {
        return vm.notes.filter(function (n) { return n.id === id })[0]
    }

    function test_saveNoteShowsEditAtOnceThenSyncs() {
        var opts = { data: personalData() }
        var c = make([entry(keepAcc, opts)])
        tryVerify(function () { return c.vm.loaded && !c.vm.syncing })
        var note = first(c.vm, "a")
        note.title = "Alpha (edited)"
        var key = c.vm.saveNote(note)
        compare(key, "fake:me@x/a")
        compare(first(c.vm, "a").title, "Alpha (edited)")   // visible before any network round trip
        compare(c.vm.unsynced, 1)
        tryVerify(function () { return c.vm.unsynced === 0 })
        var server = opts.data.notes.filter(function (n) { return n.id === "a" })[0]
        compare(server.title, "Alpha (edited)")
        compare(c.vm.error, "")
    }

    function test_newNoteIsCreatedInTheChosenAccount() {
        var opts = { data: workData() }
        var c = make([entry(keepAcc, { data: personalData() }), entry(workAcc, opts)])
        tryVerify(function () { return c.vm.notes.length === 3 })
        var key = c.vm.saveNote({ id: "", accountKey: "fake:work", type: "NOTE", title: "Fresh", text: "x",
                                  items: [], labels: [] })
        verify(key.indexOf("fake:work/") === 0)
        tryVerify(function () { return c.vm.unsynced === 0 })
        compare(opts.data.notes.length, 2)
        compare(c.vm.notes.filter(function (n) { return n.title === "Fresh" }).length, 1)
    }

    function test_failedSendKeepsEditAndRetriesOnRefresh() {
        var opts = { data: personalData() }
        var c = make([entry(keepAcc, opts)])
        tryVerify(function () { return c.vm.loaded && !c.vm.syncing })
        opts.fail = new Errors.ProviderError("network")
        var note = first(c.vm, "a")
        note.title = "Offline edit"
        c.vm.saveNote(note)
        tryVerify(function () { return c.vm.error === "network" && !c.vm.syncing })
        compare(c.vm.unsynced, 1)
        compare(first(c.vm, "a").title, "Offline edit")      // still shown
        opts.fail = null
        c.vm.refresh()
        tryVerify(function () { return c.vm.unsynced === 0 })
        compare(opts.data.notes.filter(function (n) { return n.id === "a" })[0].title, "Offline edit")
    }

    function test_unsyncedEditsSurviveARestartThroughTheCache() {
        var opts = { data: personalData() }
        var c = make([entry(keepAcc, opts)])
        tryVerify(function () { return c.vm.loaded && !c.vm.syncing })
        opts.fail = new Errors.ProviderError("network")
        var note = first(c.vm, "a")
        note.title = "Survives restart"
        c.vm.saveNote(note)
        tryVerify(function () { return c.vm.error === "network" && !c.vm.syncing })

        var accounts2 = accountsComp.createObject(tc, {
            sessions: [entry(keepAcc, { data: personalData(), fail: new Errors.ProviderError("network") })] })
        var restarted = vmComp.createObject(tc, { accounts: accounts2, cache: c.cache, writeDelay: 20 })
        compare(restarted.unsynced, 1)
        compare(restarted.notes.filter(function (n) { return n.id === "a" })[0].title, "Survives restart")
    }

    function test_removeNoteHidesItAndDeletesOnServer() {
        var opts = { data: personalData() }
        var c = make([entry(keepAcc, opts)])
        tryVerify(function () { return c.vm.loaded && !c.vm.syncing })
        verify(c.vm.removeNote(first(c.vm, "a")))
        verify(first(c.vm, "a") === undefined)
        tryVerify(function () { return c.vm.unsynced === 0 })
        verify(opts.data.notes.every(function (n) { return n.id !== "a" }))
    }

    function test_trashAndRestoreGoThroughSaveNote() {
        var opts = { data: personalData() }
        var c = make([entry(keepAcc, opts)])
        tryVerify(function () { return c.vm.loaded && !c.vm.syncing })
        var note = first(c.vm, "a")
        note.trashed = true
        c.vm.saveNote(note)
        verify(first(c.vm, "a") === undefined)
        c.vm.select("trash")
        verify(first(c.vm, "a") !== undefined)
    }

    function test_readOnlyProviderIsNotWritten() {
        var fakeSession = Fake.createSession(keepAcc, "s", { data: personalData() })
        var readOnly = {
            account: keepAcc,
            provider: { id: "ro", name: "RO", icon: "x", capabilities: { labels: "none", archive: true, trash: true, write: false } },
            session: fakeSession
        }
        var c = make([readOnly])
        tryVerify(function () { return c.vm.loaded })
        verify(!c.vm.canWrite("fake:me@x"))
        compare(c.vm.saveNote({ id: "a", accountKey: "fake:me@x", type: "NOTE", title: "x", items: [], labels: [] }), "")
        compare(c.vm.unsynced, 0)
    }

    function test_unknownAccountIsRejected() {
        var c = make([entry(keepAcc, { data: personalData() })])
        tryVerify(function () { return c.vm.loaded })
        compare(c.vm.saveNote({ id: "a", accountKey: "nope", type: "NOTE", title: "x", items: [], labels: [] }), "")
        verify(!c.vm.removeNote({ id: "a", accountKey: "nope" }))
    }

    function test_viewOnlyFieldsAreNotPassedToTheProvider() {
        var seen = null
        var base = Fake.createSession(keepAcc, "s", { data: personalData() })
        var spy = {
            createState: base.createState, restoreState: base.restoreState, sync: base.sync,
            notes: base.notes, labels: base.labels, pending: base.pending, remove: base.remove,
            commit: function (state, snapshot) { seen = snapshot; return base.commit(state, snapshot) }
        }
        var c = make([{ account: keepAcc, provider: { id: "fake", name: "Fake", icon: "x", capabilities: Fake.capabilities }, session: spy }])
        tryVerify(function () { return c.vm.loaded && !c.vm.syncing })
        var note = first(c.vm, "b")      // carries key, accountKey, providerId, label keys
        c.vm.saveNote(note)
        verify(seen !== null)
        verify(!("key" in seen))
        verify(!("accountKey" in seen))
        verify(!("providerId" in seen))
        compare(seen.labels[0].id, "L1")
        verify(!("key" in seen.labels[0]))
    }
}
