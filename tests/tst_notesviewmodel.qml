import QtQuick
import QtTest
import "../package/contents/ui/viewmodel" as VM
import "../package/contents/code/providers/fake.js" as Fake
import "../package/contents/code/providers/local/index.js" as Local
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
            property int flushed: 0
            function load(k) { return Promise.resolve(store[k] || "") }
            function save(k, v) { store[k] = v; return Promise.resolve() }
            function remove(k) { delete store[k]; removed.push(k); return Promise.resolve() }
            function flush() { flushed++ }
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
        c.vm.flushCache()
        verify(c.cache.store["fake:me@x"].length > 0)

        // A second ViewModel starts from the cache even when the network is down.
        var offlineEntry = entry(keepAcc, { fail: new Errors.ProviderError("network") })
        var accounts2 = accountsComp.createObject(tc, { sessions: [offlineEntry] })
        var offline = vmComp.createObject(tc, { accounts: accounts2, cache: c.cache })
        tryVerify(function () { return offline.loaded })
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
        return vm.rail.map(function (i) { return i.type === "header" ? "#" + i.accountKey : (i.type === "addLabel" ? "+" + i.accountKey : i.key) }).join()
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

    function test_unlabeledPerAccountInMultiAccountRail() {
        var c = make([entry(keepAcc, { data: personalData() }), entry(workAcc, { data: workData() })])
        tryVerify(function () { return c.vm.notes.length === 3 })
        compare(groupCount(c.vm, "unlabeled:fake:me@x"), 1)
        c.vm.select("unlabeled:fake:me@x")
        compare(ids(c.vm), "a")                               // only that account's unlabeled note
        verify(c.vm.canDrop("fake:me@x/b", "unlabeled:fake:me@x"))
        verify(!c.vm.canDrop("fake:me@x/b", "unlabeled:fake:work"))   // another account's group
        c.vm.select("unlabeled:fake:gone")                    // unknown account falls back to everything
        compare(c.vm.selected, "all")
    }

    function test_railSingleAccountIsFlat() {
        var c = make([entry(keepAcc, { data: personalData() })])
        tryVerify(function () { return c.vm.loaded })
        compare(railKeys(c.vm), "all,unlabeled,label:fake:me@x|L1,+fake:me@x,archive,trash")
        verify(c.vm.railVisible)
        compare(groupCount(c.vm, "all"), 2)
        compare(groupCount(c.vm, "unlabeled"), 1)
        compare(groupCount(c.vm, "label:fake:me@x|L1"), 1)
        compare(groupCount(c.vm, "archive"), 1)
        compare(groupCount(c.vm, "trash"), 1)
        compare(c.vm.rail[0].kind, "all")
        compare(c.vm.rail[2].name, "Work")
        verify(c.vm.rail[1].droppable && c.vm.rail[2].droppable && !c.vm.rail[0].droppable)
        verify(c.vm.rail[c.vm.rail.length - 1].droppable)
    }

    function test_railMultiAccountGroupsLabelsUnderAccountHeaders() {
        var c = make([entry(keepAcc, { data: personalData() }), entry(workAcc, { data: workData() })])
        tryVerify(function () { return c.vm.notes.length === 3 })
        compare(railKeys(c.vm), "all,#fake:me@x,unlabeled:fake:me@x,label:fake:me@x|L1,#fake:work,unlabeled:fake:work,label:fake:work|L1,archive,trash")
        compare(c.vm.rail[1].name, "me@x")
        verify(c.vm.rail[1].canAddLabel)               // the header carries the "new label" button
        // Counts follow the account scope.
        c.vm.selectAccount("fake:work")
        compare(railKeys(c.vm), "all,unlabeled,label:fake:work|L1,+fake:work,archive,trash")
        compare(groupCount(c.vm, "all"), 1)
        c.vm.selectAccount("")
        compare(groupCount(c.vm, "all"), 3)
    }

    // --- label editing

    function noEditEntry(account, opts) {
        var e = entry(account, opts)
        var caps = JSON.parse(JSON.stringify(Fake.capabilities))
        caps.labelEdit = false
        e.provider = { id: Fake.id, name: Fake.name, icon: Fake.icon, capabilities: caps }
        return e
    }

    function test_createLabelShowsInRailAndIsQueued() {
        var c = make([entry(keepAcc, { data: personalData() })])
        tryVerify(function () { return c.vm.loaded })
        var made = c.vm.createLabel("fake:me@x", "  Ideas ")
        compare(made.name, "Ideas")
        compare(made.key, "fake:me@x|" + made.id)
        verify(railKeys(c.vm).indexOf("label:" + made.key) >= 0)
        compare(c.vm.unsynced, 1)
        tryVerify(function () { return c.vm.unsynced === 0 })   // sent by the write timer
    }

    function test_createLabelRejectsEmptyAndTakenNames() {
        var c = make([entry(keepAcc, { data: personalData() })])
        tryVerify(function () { return c.vm.loaded })
        compare(c.vm.createLabel("fake:me@x", "  "), null)
        compare(c.vm.createLabel("fake:me@x", "work"), null)   // "Work" exists, ignoring case
        compare(c.vm.labelNameError("fake:me@x", ""), "empty")
        compare(c.vm.labelNameError("fake:me@x", "WORK"), "exists")
        compare(c.vm.labelNameError("fake:me@x", "WORK", "L1"), "")   // renaming it to itself is fine
        compare(c.vm.labelNameError("fake:me@x", "Fresh"), "")
        compare(c.vm.labels.length, 1)
    }

    function test_renameLabelUpdatesNotesAndKeepsSelection() {
        var c = make([entry(keepAcc, { data: personalData() })])
        tryVerify(function () { return c.vm.loaded })
        c.vm.select("label:fake:me@x|L1")
        verify(c.vm.renameLabel("fake:me@x|L1", "Job"))
        compare(c.vm.selected, "label:fake:me@x|L1")
        compare(ids(c.vm), "b")
        compare(c.vm.notes[0].labels[0].name, "Job")
        verify(!c.vm.renameLabel("fake:me@x|L1", ""))
        verify(!c.vm.renameLabel("fake:me@x|nope", "X"))
    }

    function test_deleteLabelKeepsNotesAndLeavesTheGroup() {
        var c = make([entry(keepAcc, { data: personalData() })])
        tryVerify(function () { return c.vm.loaded })
        c.vm.select("label:fake:me@x|L1")
        verify(c.vm.deleteLabel("fake:me@x|L1"))
        compare(c.vm.selected, "all")
        compare(ids(c.vm), "b,a")   // the note stays, unlabeled now
        compare(c.vm.labels.length, 0)
        verify(!c.vm.deleteLabel("fake:me@x|L1"))
    }

    function test_accountWithoutLabelsStillOffersToCreateOne() {
        var c = make([entry(keepAcc, { data: personalData() }), entry(workAcc, { data: { notes: [], labels: [] } })])
        tryVerify(function () { return c.vm.loaded })
        verify(railKeys(c.vm).indexOf("#fake:work,unlabeled:fake:work,archive") >= 0)
        verify(c.vm.rail.filter(function (i) { return i.accountKey === "fake:work" && i.type === "header" })[0].canAddLabel)
    }

    function test_providerWithoutLabelEditHasNoLabelCommands() {
        var c = make([noEditEntry(keepAcc, { data: personalData() })])
        tryVerify(function () { return c.vm.loaded })
        verify(!c.vm.canEditLabels("fake:me@x"))
        compare(c.vm.createLabel("fake:me@x", "X"), null)
        verify(!c.vm.renameLabel("fake:me@x|L1", "X"))
        verify(!c.vm.deleteLabel("fake:me@x|L1"))
        compare(railKeys(c.vm), "all,unlabeled,label:fake:me@x|L1,archive,trash")
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
        c.vm.flushCache()

        var accounts2 = accountsComp.createObject(tc, {
            sessions: [entry(keepAcc, { data: personalData(), fail: new Errors.ProviderError("network") })] })
        var restarted = vmComp.createObject(tc, { accounts: accounts2, cache: c.cache, writeDelay: 20 })
        tryCompare(restarted, "unsynced", 1)
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

    function test_noteByKeyFindsNotesOutsideTheSelectedGroup() {
        var c = make([entry(keepAcc, { data: personalData() })])
        tryVerify(function () { return c.vm.loaded })
        c.vm.select("trash")
        verify(c.vm.noteByKey("fake:me@x/a") !== null)      // not in the trash group, still found
        verify(c.vm.noteByKey("fake:me@x/nope") === null)
        verify(c.vm.noteByKey("other/a") === null)
    }

    function test_capabilitiesOfAnAccount() {
        var c = make([entry(keepAcc, { data: personalData() })])
        tryVerify(function () { return c.vm.loaded })
        compare(c.vm.capabilities("fake:me@x").labels, "multi")
        verify(c.vm.capabilities("nope") === null)
    }

    // --- drag & drop, undoable actions, trash, new notes (stage E)

    function entryCaps(account, opts, caps) {
        var e = entry(account, opts)
        e.provider.capabilities = Object.assign({}, Fake.capabilities, caps)
        return e
    }

    function labelsOfNote(vm, id) {
        return vm.noteByKey("fake:me@x/" + id).labels.map(function (l) { return l.id }).join()
    }

    function test_dropOnLabelAddsItAndKeepsTheOthers() {
        var data = personalData()
        data.labels.push({ id: "L2", name: "Home" })
        var c = make([entry(keepAcc, { data: data })])
        tryVerify(function () { return c.vm.loaded })
        verify(c.vm.canDrop("fake:me@x/b", "label:fake:me@x|L2"))
        verify(c.vm.dropNote("fake:me@x/b", "label:fake:me@x|L2"))
        compare(labelsOfNote(c.vm, "b"), "L1,L2")
        compare(c.vm.unsynced, 1)
    }

    function test_dragOutOfALabelGroupRemovesOnlyThatLabel() {
        var data = personalData()
        data.labels.push({ id: "L2", name: "Home" }, { id: "L3", name: "Misc" })
        data.notes.forEach(function (n) { if (n.id === "b") n.labels = [{ id: "L1", name: "Work" }, { id: "L3", name: "Misc" }] })
        var c = make([entry(keepAcc, { data: data })])
        tryVerify(function () { return c.vm.loaded })
        c.vm.select("label:fake:me@x|L1")
        verify(c.vm.dropNote("fake:me@x/b", "label:fake:me@x|L2"))
        compare(labelsOfNote(c.vm, "b"), "L3,L2")           // L1 (the source group) is gone, L3 stays
    }

    function test_dropFromAllKeepsExistingLabels() {
        var data = personalData()
        data.labels.push({ id: "L2", name: "Home" })
        var c = make([entry(keepAcc, { data: data })])
        tryVerify(function () { return c.vm.loaded })
        verify(c.vm.dropNote("fake:me@x/b", "label:fake:me@x|L2"))
        compare(labelsOfNote(c.vm, "b"), "L1,L2")
    }

    function test_dropOnTheSameLabelOrAllIsRefused() {
        var c = make([entry(keepAcc, { data: personalData() })])
        tryVerify(function () { return c.vm.loaded })
        verify(!c.vm.canDrop("fake:me@x/b", "label:fake:me@x|L1"))   // already there
        verify(!c.vm.canDrop("fake:me@x/a", "all"))
        verify(!c.vm.dropNote("fake:me@x/a", "all"))
        compare(c.vm.unsynced, 0)
    }

    function test_dropOnArchiveAndTrashMovesTheNote() {
        var c = make([entry(keepAcc, { data: personalData() })])
        tryVerify(function () { return c.vm.loaded })
        verify(c.vm.canDrop("fake:me@x/a", "archive"))
        verify(c.vm.canDrop("fake:me@x/a", "trash"))
        verify(c.vm.dropNote("fake:me@x/a", "archive"))
        verify(c.vm.noteByKey("fake:me@x/a").archived)
        verify(!c.vm.canDrop("fake:me@x/a", "archive"))
        verify(c.vm.dropNote("fake:me@x/b", "trash"))
        verify(c.vm.noteByKey("fake:me@x/b").trashed)
    }

    function test_dropOnNoLabelClearsAllLabels() {
        var c = make([entry(keepAcc, { data: personalData() })])
        tryVerify(function () { return c.vm.loaded })
        verify(!c.vm.canDrop("fake:me@x/a", "unlabeled"))             // nothing to remove
        verify(c.vm.dropNote("fake:me@x/b", "unlabeled"))
        compare(labelsOfNote(c.vm, "b"), "")
        c.vm.select("unlabeled")
        verify(c.vm.notes.some(function (n) { return n.id === "b" }))
    }

    function test_dropIntoAnotherAccountsLabelIsRefused() {
        var c = make([entry(keepAcc, { data: personalData() }), entry(workAcc, { data: workData() })])
        tryVerify(function () { return c.vm.notes.length === 3 })
        // "a" belongs to me@x, the label to the work account (same label id L1 in both accounts)
        verify(!c.vm.canDrop("fake:me@x/a", "label:fake:work|L1"))
        verify(c.vm.canDrop("fake:me@x/a", "label:fake:me@x|L1"))
    }

    function test_singleCategoryProviderReplacesTheLabel() {
        var data = personalData()
        data.labels.push({ id: "L2", name: "Home" })
        var c = make([entryCaps(keepAcc, { data: data }, { labels: "single" })])
        tryVerify(function () { return c.vm.loaded })
        verify(c.vm.dropNote("fake:me@x/b", "label:fake:me@x|L2"))
        compare(labelsOfNote(c.vm, "b"), "L2")
    }

    function test_providerWithoutLabelsRefusesDrops() {
        var c = make([entryCaps(keepAcc, { data: personalData() }, { labels: "none" })])
        tryVerify(function () { return c.vm.loaded })
        verify(!c.vm.canDrop("fake:me@x/b", "unlabeled"))
    }

    function test_dropCanBeUndone() {
        var c = make([entry(keepAcc, { data: personalData() })])
        tryVerify(function () { return c.vm.loaded })
        c.vm.dropNote("fake:me@x/b", "unlabeled")
        compare(c.vm.lastAction.kind, "unlabeled")
        compare(c.vm.lastAction.noteKey, "fake:me@x/b")
        verify(c.vm.undoLast())
        compare(labelsOfNote(c.vm, "b"), "L1")
        verify(c.vm.lastAction === null)
    }

    function test_trashArchiveAreUndoable() {
        var c = make([entry(keepAcc, { data: personalData() })])
        tryVerify(function () { return c.vm.loaded })
        verify(c.vm.trashNote("fake:me@x/a"))
        compare(c.vm.lastAction.kind, "trashed")
        verify(c.vm.noteByKey("fake:me@x/a").trashed)
        verify(c.vm.undoLast())
        verify(!c.vm.noteByKey("fake:me@x/a").trashed)

        verify(c.vm.archiveNote("fake:me@x/a", true))
        compare(c.vm.lastAction.kind, "archived")
        verify(c.vm.noteByKey("fake:me@x/a").archived)
        c.vm.dismissAction()
        verify(c.vm.lastAction === null)
        verify(!c.vm.undoLast())
    }

    function test_pinColorRestoreGoThroughUpdateNote() {
        var c = make([entry(keepAcc, { data: personalData() })])
        tryVerify(function () { return c.vm.loaded })
        verify(c.vm.setPinned("fake:me@x/a", true))
        verify(c.vm.noteByKey("fake:me@x/a").pinned)
        verify(c.vm.setColor("fake:me@x/a", "RED"))
        compare(c.vm.noteByKey("fake:me@x/a").color, "RED")
        verify(c.vm.restoreNote("fake:me@x/d"))
        verify(!c.vm.noteByKey("fake:me@x/d").trashed)
        verify(!c.vm.updateNote("fake:me@x/nope", { pinned: true }))
    }

    function test_deleteForeverAndEmptyTrash() {
        var opts = { data: personalData() }
        opts.data.notes.push(note("e", { title: "Epsilon", trashed: true, order: 1 }))
        var c = make([entry(keepAcc, opts)])
        tryVerify(function () { return c.vm.loaded && !c.vm.syncing })
        verify(c.vm.deleteForever("fake:me@x/d"))
        verify(c.vm.noteByKey("fake:me@x/d") === null)
        compare(c.vm.emptyTrash(), 1)          // only "e" was left in the trash
        verify(c.vm.noteByKey("fake:me@x/e") === null)
        verify(c.vm.noteByKey("fake:me@x/a") !== null)
        tryVerify(function () { return c.vm.unsynced === 0 })
        verify(opts.data.notes.every(function (n) { return n.id !== "d" && n.id !== "e" }))
    }

    function test_emptyTrashRespectsTheAccountFilter() {
        var wd = workData()
        wd.notes.push(note("wt", { title: "Work trash", trashed: true, order: 1 }))
        var c = make([entry(keepAcc, { data: personalData() }), entry(workAcc, { data: wd })])
        tryVerify(function () { return c.vm.notes.length === 3 })
        c.vm.selectAccount("fake:work")
        compare(c.vm.emptyTrash(), 1)
        verify(c.vm.noteByKey("fake:me@x/d") !== null)   // the other account's trash is untouched
    }

    // --- new notes

    function test_newNoteIsADraftUntilFirstSave() {
        var c = make([entry(keepAcc, { data: personalData() })])
        tryVerify(function () { return c.vm.loaded })
        verify(c.vm.openNewNote("NOTE"))
        compare(c.vm.currentNoteKey, "<new>")
        compare(c.vm.currentNote.id, "")
        compare(c.vm.currentNote.accountKey, "fake:me@x")
        compare(c.vm.unsynced, 0)                       // nothing is stored yet
        c.vm.closeNote()
        compare(c.vm.notes.length, 2)                   // closing untouched leaves nothing behind
        verify(c.vm.currentNote === null)
    }

    function test_savingTheDraftCreatesTheNoteAndKeepsItOpen() {
        var opts = { data: personalData() }
        var c = make([entry(keepAcc, opts)])
        tryVerify(function () { return c.vm.loaded && !c.vm.syncing })
        c.vm.openNewNote("NOTE")
        var draft = JSON.parse(JSON.stringify(c.vm.currentNote))
        draft.title = "Fresh"
        var key = c.vm.saveNote(draft)
        verify(key.indexOf("fake:me@x/") === 0)
        compare(c.vm.currentNoteKey, "<new>")           // the editor keeps working on the same key
        compare(c.vm.currentNote.title, "Fresh")
        compare(c.vm.noteByKey("<new>").id, c.vm.noteByKey(key).id)
        tryVerify(function () { return c.vm.unsynced === 0 })
        verify(opts.data.notes.some(function (n) { return n.title === "Fresh" }))
    }

    function test_newListStartsWithOneEmptyItem() {
        var c = make([entry(keepAcc, { data: personalData() })])
        tryVerify(function () { return c.vm.loaded })
        c.vm.openNewNote("LIST")
        compare(c.vm.currentNote.type, "LIST")
        compare(c.vm.currentNote.items.length, 1)
        compare(c.vm.currentNote.items[0].text, "")
    }

    function test_newNoteGoesToTheAccountAndLabelInView() {
        var c = make([entry(keepAcc, { data: personalData() }), entry(workAcc, { data: workData() })])
        tryVerify(function () { return c.vm.notes.length === 3 })
        c.vm.selectAccount("fake:work")
        c.vm.openNewNote("NOTE")
        compare(c.vm.currentNote.accountKey, "fake:work")
        c.vm.closeNote()
        c.vm.selectAccount("")
        c.vm.select("label:fake:me@x|L1")
        c.vm.openNewNote("NOTE")
        compare(c.vm.currentNote.accountKey, "fake:me@x")
        compare(c.vm.currentNote.labels.map(function (l) { return l.id }).join(), "L1")
    }

    function test_newNoteInArchiveViewIsArchived() {
        var c = make([entry(keepAcc, { data: personalData() })])
        tryVerify(function () { return c.vm.loaded })
        c.vm.select("archive")
        c.vm.openNewNote("NOTE")
        verify(c.vm.currentNote.archived)
    }

    function test_newNoteRemembersTheLastUsedAccount() {
        var c = make([entry(keepAcc, { data: personalData() }), entry(workAcc, { data: workData() })])
        tryVerify(function () { return c.vm.notes.length === 3 })
        c.vm.openNewNote("NOTE")
        c.vm.currentNote.accountKey                      // default: first account in key order
        var draft = JSON.parse(JSON.stringify(c.vm.currentNote))
        draft.accountKey = "fake:work"
        draft.title = "To work"
        c.vm.saveNote(draft)
        c.vm.closeNote()
        c.vm.openNewNote("NOTE")
        compare(c.vm.currentNote.accountKey, "fake:work")
    }

    function test_noWritableAccountMeansNoNewNote() {
        var ro = entryCaps(keepAcc, { data: personalData() }, { write: false })
        var c = make([ro])
        tryVerify(function () { return c.vm.loaded })
        verify(!c.vm.openNewNote("NOTE"))
        compare(c.vm.writableAccounts().length, 0)
    }

    function test_labelsOfAnAccount() {
        var c = make([entry(keepAcc, { data: personalData() }), entry(workAcc, { data: workData() })])
        tryVerify(function () { return c.vm.notes.length === 3 })
        compare(c.vm.labelsOf("fake:work").length, 1)
        compare(c.vm.labelsOf("fake:work")[0].name, "Work")
        compare(c.vm.labelsOf("nope").length, 0)
    }

    function test_canCreateFollowsWritableAccounts() {
        var c = make([entry(keepAcc, { data: personalData() })])
        tryVerify(function () { return c.vm.loaded })
        verify(c.vm.canCreate)
        var ro = make([entryCaps(keepAcc, { data: personalData() }, { write: false })])
        tryVerify(function () { return ro.vm.loaded })
        verify(!ro.vm.canCreate)
        verify(!make([]).vm.canCreate)
    }

    // --- manual order of notes

    function orderedData(orders) {
        var notes = [{ id: "P", title: "Pinned", pinned: true, order: 500 }]
        orders.forEach(function (o, i) { notes.push({ id: "n" + o, title: "N" + o, order: o }) })
        return { labels: [], notes: notes }
    }
    function visibleIds(vm) { return vm.notes.map(function (n) { return n.id }).join() }

    function test_reorderIsOnlyEnabledWhereItMakesSense() {
        var c = make([entry(keepAcc, { data: orderedData([40, 30]) })])
        tryVerify(function () { return c.vm.loaded })
        verify(c.vm.reorderEnabled)
        c.vm.searchText = "N"
        verify(!c.vm.reorderEnabled)                   // a filtered list has no meaningful positions
        c.vm.searchText = ""
        c.vm.select("trash")
        verify(!c.vm.reorderEnabled)
        c.vm.select("all")

        var two = make([entry(keepAcc, { data: orderedData([40, 30]) }), entry(workAcc, { data: workData() })])
        tryVerify(function () { return two.vm.notes.length > 3 })
        verify(two.vm.reorderEnabled)                  // the mixed list has the widget's own order
        verify(two.vm.showAccounts)                    // cards say where they come from
        two.vm.selectAccount("fake:work")
        verify(two.vm.reorderEnabled)
        verify(!two.vm.showAccounts)
    }

    function test_groupOfOneAccountKeepsItsOwnOrderEvenWithSeveralAccounts() {
        var two = make([entry(keepAcc, { data: orderedData([40, 30]) }), entry(workAcc, { data: workData() })])
        tryVerify(function () { return two.vm.notes.length > 3 })
        two.vm.select("unlabeled:fake:me@x")
        compare(two.vm.scopeAccountKey, "fake:me@x")
        verify(two.vm.reorderEnabled)
        verify(!two.vm.showAccounts)
        compare(visibleIds(two.vm), "P,n40,n30")       // provider order, not update time
        verify(two.vm.canMoveTo("fake:me@x/n30", 1))
        verify(two.vm.moveNote("fake:me@x/n30", 1))
        two.vm.select("all")
        verify(two.vm.reorderEnabled)
    }

    function test_moveBoundsKeepPinnedAndOthersApart() {
        var c = make([entry(keepAcc, { data: orderedData([40, 30]) })])
        tryVerify(function () { return c.vm.notes.length > 2 })
        var pinnedKey = c.vm.notes[0].key        // "P" is pinned (see orderedData)
        var b = c.vm.moveBounds(pinnedKey)
        compare(b.from, 0)
        compare(b.to, 0)
        var other = c.vm.moveBounds(c.vm.notes[1].key)
        compare(other.from, 1)
        verify(!c.vm.moveBounds("nope"))
    }

    function test_mixedListKeepsTheOrderTheUserGaveIt() {
        var two = make([entry(keepAcc, { data: orderedData([40, 30]) }), entry(workAcc, { data: workData() })])
        tryVerify(function () { return two.vm.notes.length > 3 })
        var keys = two.vm.notes.map(function (n) { return n.key })
        var last = keys[keys.length - 1]
        verify(two.vm.canMoveTo(last, 0) || two.vm.canMoveTo(last, 1))
        var to = two.vm.canMoveTo(last, 0) ? 0 : 1
        verify(two.vm.moveNote(last, to))
        compare(two.vm.notes[to].key, last)
        compare(two.vm.mixedOrder[to], last)
        verify(two.vm.undoLast())
        compare(two.vm.notes[keys.length - 1].key, last)
    }

    function test_moveBetweenNeighboursTakesTheMiddleOrder() {
        var opts = { data: orderedData([40, 30, 20, 10]) }
        var c = make([entry(keepAcc, opts)])
        tryVerify(function () { return c.vm.loaded && !c.vm.syncing })
        compare(visibleIds(c.vm), "P,n40,n30,n20,n10")
        // Insert n10 between n40 and n30: index 2 of the list without it [P, n40, n30, n20].
        verify(c.vm.canMoveTo("fake:me@x/n10", 2))
        verify(c.vm.moveNote("fake:me@x/n10", 2))
        compare(visibleIds(c.vm), "P,n40,n10,n30,n20")
        compare(c.vm.noteByKey("fake:me@x/n10").order, 35)
        compare(c.vm.unsynced, 1)
        tryVerify(function () { return c.vm.unsynced === 0 })
        compare(opts.data.notes.filter(function (n) { return n.id === "n10" })[0].order, 35)
    }

    function test_moveToTheEdgesOfTheSection() {
        var c = make([entry(keepAcc, { data: orderedData([40, 30, 20, 10]) })])
        tryVerify(function () { return c.vm.loaded && !c.vm.syncing })
        verify(c.vm.moveNote("fake:me@x/n20", 1))      // first among the unpinned
        compare(visibleIds(c.vm), "P,n20,n40,n30,n10")
        verify(c.vm.noteByKey("fake:me@x/n20").order > 40)
        verify(c.vm.moveNote("fake:me@x/n40", 4))      // last (list without it has 4 items)
        compare(visibleIds(c.vm), "P,n20,n30,n10,n40")
        verify(c.vm.noteByKey("fake:me@x/n40").order < 10)
    }

    function test_pinnedAndOthersStayInTheirSections() {
        var c = make([entry(keepAcc, { data: orderedData([40, 30]) })])
        tryVerify(function () { return c.vm.loaded })
        verify(!c.vm.canMoveTo("fake:me@x/n40", 0))    // above the pinned note
        verify(c.vm.canMoveTo("fake:me@x/n40", 1))
        verify(!c.vm.canMoveTo("fake:me@x/P", 1))      // below an unpinned note
        verify(c.vm.canMoveTo("fake:me@x/P", 0))
        verify(!c.vm.moveNote("fake:me@x/n40", 0))
    }

    function test_movingToTheSamePlaceChangesNothing() {
        var c = make([entry(keepAcc, { data: orderedData([40, 30, 20]) })])
        tryVerify(function () { return c.vm.loaded && !c.vm.syncing })
        verify(!c.vm.moveNote("fake:me@x/n30", 2))     // already between n40 and n20
        compare(c.vm.unsynced, 0)
        verify(c.vm.lastAction === null)
    }

    function test_noRoomBetweenNeighboursRenumbersTheSection() {
        var c = make([entry(keepAcc, { data: orderedData([11, 10, 9, 8]) })])
        tryVerify(function () { return c.vm.loaded && !c.vm.syncing })
        verify(c.vm.moveNote("fake:me@x/n8", 2))       // between 11 and 10: no integer in between
        compare(visibleIds(c.vm), "P,n11,n8,n10,n9")
        var orders = c.vm.notes.filter(function (n) { return !n.pinned }).map(function (n) { return n.order })
        for (var i = 1; i < orders.length; i++)
            verify(orders[i - 1] > orders[i], "strictly descending: " + orders.join())
        verify(c.vm.unsynced > 1)                      // several notes were renumbered
    }

    function test_moveCanBeUndone() {
        var c = make([entry(keepAcc, { data: orderedData([40, 30, 20]) })])
        tryVerify(function () { return c.vm.loaded && !c.vm.syncing })
        verify(c.vm.moveNote("fake:me@x/n20", 1))
        compare(visibleIds(c.vm), "P,n20,n40,n30")
        compare(c.vm.lastAction.kind, "moved")
        verify(c.vm.undoLast())
        compare(visibleIds(c.vm), "P,n40,n30,n20")
        verify(c.vm.lastAction === null)
    }

    function test_editingANoteKeepsItsPosition() {
        var c = make([entry(keepAcc, { data: orderedData([40, 30, 20]) })])
        tryVerify(function () { return c.vm.loaded && !c.vm.syncing })
        c.vm.moveNote("fake:me@x/n20", 1)
        var note = c.vm.noteByKey("fake:me@x/n20")
        note.title = "Edited"
        c.vm.saveNote(note)
        compare(visibleIds(c.vm), "P,n20,n40,n30")      // the edit did not undo the move
    }

    function test_noteTextForTheClipboard() {
        var c = make([entry(keepAcc, { data: personalData() })])
        tryVerify(function () { return c.vm.loaded })
        var n = c.vm.noteByKey("fake:me@x/a")
        var text = c.vm.noteText("fake:me@x/a")
        verify(text.indexOf(n.title) === 0)
        compare(c.vm.noteText("missing"), "")
    }

    function test_cacheIsWrittenOnceAfterAQuietPeriod() {
        var c = make([entry(keepAcc, { data: personalData() })])
        tryVerify(function () { return c.vm.loaded })
        c.vm.cacheDelay = 100000                         // never by timer in this test
        c.vm.flushCache()
        var saves = 0
        var before = c.cache.store["fake:me@x"]
        var note = first(c.vm, "a")
        note.title = "one"
        c.vm.saveNote(note)
        note.title = "two"
        c.vm.saveNote(note)
        compare(c.cache.store["fake:me@x"], before)      // nothing written per edit
        c.vm.flushCache()
        verify(c.cache.store["fake:me@x"] !== before)
        verify(c.cache.store["fake:me@x"].indexOf("two") >= 0)
    }

    function test_cachedNotesAppearWhileTheFirstSyncIsStillToCome() {
        var c = make([entry(keepAcc, { data: personalData() })])
        tryVerify(function () { return c.vm.loaded })
        c.vm.flushCache()
        // A slow cache: the account shows nothing until it answers, then the cached notes, then the server's.
        var release = null
        var slow = {
            load: function (k) { return new Promise(function (resolve) { release = function () { resolve(c.cache.store[k]) } }) },
            save: function () { return Promise.resolve() },
            remove: function () { return Promise.resolve() }
        }
        var accounts2 = accountsComp.createObject(tc, { sessions: [entry(keepAcc, { data: personalData() })] })
        var vm2 = vmComp.createObject(tc, { accounts: accounts2, cache: slow })
        compare(vm2.notes.length, 0)
        verify(!vm2.syncing)                              // the first sync waits for the cache
        release()
        tryVerify(function () { return vm2.loaded })
        compare(ids(vm2), "b,a")
    }

    function test_flushOnDestructionAsksTheCacheToWriteEverything() {
        var c = make([entry(keepAcc, { data: personalData() })])
        tryVerify(function () { return c.vm.loaded })
        var note = first(c.vm, "a")
        note.title = "Last words"
        c.vm.saveNote(note)
        c.vm.destroy()
        wait(10)
        verify(c.cache.store["fake:me@x"].indexOf("Last words") >= 0)
        compare(c.cache.flushed, 1)
    }

    function test_savingOneNoteKeepsTheListAndOrderConsistent() {
        var c = make([entry(keepAcc, { data: personalData() })])
        tryVerify(function () { return c.vm.loaded })
        var before = ids(c.vm)
        var note = first(c.vm, "a")
        note.title = "Edited"
        c.vm.saveNote(note)
        compare(ids(c.vm), before)
        compare(first(c.vm, "a").title, "Edited")
        compare(c.vm.noteByKey("fake:me@x/a").title, "Edited")
    }

    // --- persistent provider (local notes)

    readonly property var localAcc: ({ key: "local:home", providerId: "local", accountId: "home", displayName: "home", meta: {} })

    function localEntry(account) {
        return {
            account: account,
            provider: { id: Local.id, name: Local.name, icon: Local.icon, capabilities: Local.capabilities },
            session: Local.createSession(account, "local", {})
        }
    }

    function test_persistentAccountIsSavedAtOnceOnEdit() {
        var c = make([localEntry(localAcc)])
        tryVerify(function () { return c.vm.loaded })
        var flushedBefore = c.cache.flushed
        var key = c.vm.saveNote({ id: "", accountKey: "local:home", type: "NOTE", title: "Mine", text: "x",
                                  items: [], labels: [], color: "DEFAULT", pinned: false, archived: false, trashed: false })
        verify(key !== "")
        // No flushCache() call and no wait for the quiet period.
        verify(c.cache.store["local:home"].indexOf("Mine") >= 0)
        verify(c.cache.flushed > flushedBefore)
    }

    function test_persistentAccountWithUnreadableDataIsLocked() {
        var c = make([localEntry(localAcc)], true)
        c.cache.store["local:home"] = "{not json"
        var accounts2 = accountsComp.createObject(tc, { sessions: [localEntry(localAcc)] })
        var vm = vmComp.createObject(tc, { accounts: accounts2, cache: c.cache })
        tryVerify(function () { return vm.error === "storage" })
        verify(!vm.canWrite("local:home"))
        compare(vm.saveNote({ id: "", accountKey: "local:home", type: "NOTE", title: "x", text: "", items: [], labels: [] }), "")
        compare(c.cache.store["local:home"], "{not json")   // the broken data is left alone
    }
}
