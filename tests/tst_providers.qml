import QtQuick
import QtTest
import "../package/contents/code/providers/contract.js" as Contract
import "../package/contents/code/providers/registry.js" as Registry
import "../package/contents/code/providers/fake.js" as Fake
import "../package/contents/code/providers/keep/index.js" as Keep
import "../package/contents/code/providers/local/index.js" as Local
import "../package/contents/code/providers/keep/gauth.js" as GAuth
import "../package/contents/code/providers/keep/keepapi.js" as KeepApi

TestCase {
    id: tc
    name: "Providers"
    when: windowShown

    readonly property string never: "1970-01-01T00:00:00.000000Z"
    readonly property string now: "2026-10-15T10:00:00.000000Z"

    function ts() { return { created: now, updated: now, trashed: never, deleted: never } }

    function keepResponse() {
        return {
            toVersion: "v1", truncated: false,
            userInfo: { labels: [{ mainId: "L1", name: "Work", timestamps: ts() }] },
            nodes: [
                { id: "n1", kind: "notes#node", parentId: "root", type: "NOTE", title: "Hi", sortValue: "7",
                  timestamps: ts(), labelIds: [{ labelId: "L1" }] },
                { id: "n1.b", kind: "notes#node", parentId: "n1", type: "LIST_ITEM", text: "body", sortValue: "1", timestamps: ts() }
            ]
        }
    }

    readonly property var account: ({ key: "keep:me@example.com", providerId: "keep", accountId: "me@example.com", meta: { androidId: "0123456789abcdef" } })

    function oauthOk(counter) {
        return function (email, master, androidId) {
            counter.n++
            return Promise.resolve({ token: "tok" + counter.n, expiry: Date.now() + 3600 * 1000 })
        }
    }

    // --- contract

    function test_keepProviderMeetsContract() {
        compare(Contract.validate(Keep).join("; "), "")
        compare(Contract.validateSession(Keep.createSession(account, "master", {}), Keep.capabilities).join("; "), "")
    }

    function test_fakeProviderMeetsContract() {
        compare(Contract.validate(Fake).join("; "), "")
        compare(Contract.validateSession(Fake.createSession(account, "s", {}), Fake.capabilities).join("; "), "")
    }

    function test_contractReportsProblems() {
        var problems = Contract.validate({ id: "x", name: "X", icon: "i", capabilities: { labels: "weird" }, credentialFields: [] })
        verify(problems.length >= 4)
        verify(problems.some(function (p) { return p.indexOf("labels must be one of") >= 0 }))
        verify(Contract.validate(null).length > 0)
    }

    function test_colorsCapabilityIsAListOfNames() {
        verify(Array.isArray(Keep.capabilities.colors))
        compare(Keep.capabilities.colors[0], "DEFAULT")
        compare(Keep.capabilities.colors.length, 12)
        verify(Contract.validate({ id: "x", name: "X", icon: "i", capabilities: {
            labels: "none", colors: true, checklists: false, nestedItems: false, pinned: false, archive: false,
            trash: false, images: false, write: false, reorder: false, offlineEdit: false
        }, credentialFields: [{ key: "k", label: "L" }], signIn: function () {}, createSession: function () {} })
            .some(function (p) { return p.indexOf("colors must be an array") >= 0 }))
    }

    function test_labelEditCapabilityRequiresLabelMethods() {
        var caps = { labelEdit: true }
        var base = { createState: 1, restoreState: 1, sync: 1, notes: 1, labels: 1 }
        var session = {}
        Object.keys(base).forEach(function (k) { session[k] = function () {} })
        var problems = Contract.validateSession(session, caps)
        verify(problems.some(function (p) { return p.indexOf("createLabel") >= 0 }))
        verify(problems.some(function (p) { return p.indexOf("deleteLabel") >= 0 }))
        verify(Contract.validateSession(session, { labelEdit: false }).length === 0)
    }

    function test_registryListsKeep() {
        verify(Registry.get("keep") !== null)
        compare(Registry.get("keep").name, "Google Keep")
        compare(Registry.get("nope"), null)
        compare(Registry.list().length, 2)
        compare(Registry.get("local").name, "Local notes")
        // Every registered provider honors the contract.
        Registry.list().forEach(function (p) { compare(Contract.validate(p).join(), "") })
    }

    // --- Keep session

    function test_keepSessionSyncAndNormalizedNotes() {
        var oauth = { n: 0 }
        var s = Keep.createSession(account, "master", {
            performOAuth: oauthOk(oauth),
            transport: function () { return Promise.resolve(keepResponse()) }
        })
        var state = s.createState()
        var done = false
        s.sync(state, []).then(function () { done = true })
        tryVerify(function () { return done })
        var notes = s.notes(state)
        compare(notes.length, 1)
        compare(notes[0].text, "body")
        compare(notes[0].order, 7)
        compare(notes[0].labels[0].name, "Work")
        compare(s.labels(state)[0].name, "Work")
    }

    function test_keepSessionReusesAuthTokenAcrossSyncs() {
        var oauth = { n: 0 }
        var seen = []
        var s = Keep.createSession(account, "master", {
            performOAuth: oauthOk(oauth),
            transport: function (token) { seen.push(token); return Promise.resolve(keepResponse()) }
        })
        var state = s.createState()
        var done = 0
        s.sync(state).then(function () { return s.sync(state) }).then(function () { done = 1 })
        tryVerify(function () { return done === 1 })
        compare(oauth.n, 1)
        compare(seen.join(), "tok1,tok1")
    }

    function test_keepSessionRefreshesTokenOn401AndRetriesOnce() {
        var oauth = { n: 0 }
        var calls = 0
        var s = Keep.createSession(account, "master", {
            performOAuth: oauthOk(oauth),
            transport: function (token) {
                calls++
                return calls === 1 ? Promise.reject(new KeepApi.KeepApiError("Unauthorized", 401))
                                   : Promise.resolve(keepResponse())
            }
        })
        var done = false
        s.sync(s.createState()).then(function () { done = true })
        tryVerify(function () { return done })
        compare(oauth.n, 2)
        compare(calls, 2)
    }

    function test_keepSessionMapsErrors() {
        function failWith(opts) {
            var s = Keep.createSession(account, "master", opts)
            var err = null
            s.sync(s.createState()).catch(function (e) { err = e })
            tryVerify(function () { return err !== null })
            return err.kind
        }
        compare(failWith({
            performOAuth: function () { return Promise.reject(new GAuth.AuthError("Network", 0)) }
        }), "network")
        compare(failWith({
            performOAuth: function () { return Promise.reject(new GAuth.AuthError("BadAuthentication", 403)) }
        }), "auth")
        compare(failWith({
            performOAuth: oauthOk({ n: 0 }),
            transport: function () { return Promise.reject(new KeepApi.KeepApiError("Network")) }
        }), "network")
        compare(failWith({
            performOAuth: oauthOk({ n: 0 }),
            transport: function () { return Promise.reject(new KeepApi.KeepApiError("Unauthorized", 401)) }
        }), "unauthorized")
        compare(failWith({
            performOAuth: oauthOk({ n: 0 }),
            transport: function () { return Promise.reject(new Error("boom")) }
        }), "failed")
    }

    function test_keepRestoreStateValidates() {
        var s = Keep.createSession(account, "master", {})
        verify(s.restoreState(null) === null)
        verify(s.restoreState({ nodes: {} }) === null)
        var ok = s.restoreState({ version: "v", nodes: {}, labels: {} })
        compare(ok.version, "v")
    }

    // --- fake provider

    function test_fakeSessionServesConfiguredNotes() {
        var opts = { data: { notes: [{ id: "a", title: "A", order: 2 }], labels: [{ id: "l", name: "L" }] } }
        var s = Fake.createSession(account, "s", opts)
        var state = s.createState()
        var done = false
        s.sync(state).then(function () { done = true })
        tryVerify(function () { return done })
        compare(s.notes(state)[0].title, "A")
        compare(s.notes(state)[0].color, "DEFAULT")   // defaults filled in
        compare(state.version, "1")
        opts.data.notes.push({ id: "b" })
        done = false
        s.sync(state).then(function () { done = true })
        tryVerify(function () { return done })
        compare(s.notes(state).length, 2)
    }

    function test_fakeSessionFailsOnDemand() {
        var opts = { fail: { kind: "network" } }
        var s = Fake.createSession(account, "s", opts)
        var err = null
        s.sync(s.createState()).catch(function (e) { err = e })
        tryVerify(function () { return err !== null })
        compare(err.kind, "network")
    }

    // --- Keep write path

    function noteSnapshot(title) {
        return { id: "", type: "NOTE", title: title, text: "body", items: [], color: "DEFAULT",
                 pinned: false, archived: false, trashed: false, labels: [] }
    }

    function keepSession(transport) {
        return Keep.createSession(account, "master", { performOAuth: oauthOk({ n: 0 }), transport: transport })
    }

    // A transport that echoes back whatever nodes it receives, like the real server does.
    function echoServer(log) {
        return function (token, body) {
            log.push(body)
            return Promise.resolve({
                toVersion: "v" + (log.length + 1), truncated: false,
                nodes: JSON.parse(JSON.stringify(body.nodes)).map(function (n) { n.serverId = "S-" + n.id; return n })
            })
        }
    }

    function test_commitIsVisibleAtOnceAndReturnsIds() {
        var s = keepSession(function () { return Promise.reject(new Error("offline")) })
        var state = s.createState()
        var note = s.commit(state, noteSnapshot("Hello"))
        verify(note.id !== "")
        compare(note.title, "Hello")
        compare(note.text, "body")
        compare(s.notes(state)[0].title, "Hello")
        compare(s.pending(state), 2)   // the note and its body item
    }

    function test_syncSendsQueueAndClearsItOnSuccess() {
        var log = []
        var s = keepSession(echoServer(log))
        var state = s.createState()
        var note = s.commit(state, noteSnapshot("Hello"))
        var done = false
        s.sync(state).then(function () { done = true })
        tryVerify(function () { return done })
        compare(log[0].nodes.length, 2)
        compare(s.pending(state), 0)
        compare(state.nodes[note.id].serverId, "S-" + note.id)   // server echo replaced the local copy
        compare(s.notes(state)[0].title, "Hello")
    }

    function test_failedSyncKeepsEditsForALaterAttempt() {
        var fail = true
        var log = []
        var s = keepSession(function (t, body) {
            return fail ? Promise.reject(new KeepApi.KeepApiError("Network")) : echoServer(log)(t, body)
        })
        var state = s.createState()
        s.commit(state, noteSnapshot("Offline edit"))
        var err = null
        s.sync(state).catch(function (e) { err = e })
        tryVerify(function () { return err !== null })
        compare(err.kind, "network")
        compare(s.pending(state), 2)
        compare(s.notes(state)[0].title, "Offline edit")   // still visible

        // The queue is part of the state, so it survives a restart through JSON.
        var restored = s.restoreState(JSON.parse(JSON.stringify(state)))
        compare(s.pending(restored), 2)

        fail = false
        var done = false
        s.sync(restored).then(function () { done = true })
        tryVerify(function () { return done })
        compare(s.pending(restored), 0)
        compare(log[0].nodes.length, 2)
    }

    function test_editMadeDuringTheRequestIsNotLostOrOverwritten() {
        var s = Keep.createSession(account, "master", { performOAuth: oauthOk({ n: 0 }) })
        var state = s.createState()
        var note = s.commit(state, noteSnapshot("v1"))
        // New server for this session: edit the note while the request is "in flight".
        var s2 = keepSession(function (token, body) {
            var edited = s.notes(state)[0]
            edited.title = "v2 (during request)"
            s.commit(state, edited)
            return Promise.resolve({
                toVersion: "v2", truncated: false,
                nodes: JSON.parse(JSON.stringify(body.nodes)).map(function (n) { n.serverId = "S-" + n.id; return n })
            })
        })
        var done = false
        s2.sync(state).then(function () { done = true })
        tryVerify(function () { return done })
        compare(s.notes(state)[0].title, "v2 (during request)")  // not overwritten by the older echo
        compare(s.pending(state), 1)                              // the newer edit still waits to be sent
    }

    function test_removeDeletesNoteAndQueuesTombstones() {
        var s = keepSession(echoServer([]))
        var state = s.createState()
        var note = s.commit(state, noteSnapshot("Doomed"))
        var done = false
        s.sync(state).then(function () { done = true })
        tryVerify(function () { return done })
        s.remove(state, note.id)
        compare(s.notes(state).length, 0)      // hidden at once
        verify(s.pending(state) > 0)
        done = false
        s.sync(state).then(function () { done = true })
        tryVerify(function () { return done })
        compare(s.pending(state), 0)
        compare(Object.keys(state.nodes).length, 0)   // tombstones are not kept
    }

    function test_restoreStateUpgradesOldCaches() {
        var s = keepSession(function () {})
        var st = s.restoreState({ version: "v", nodes: {}, labels: {} })
        compare(s.pending(st), 0)
        compare(st.rev, 0)
    }

    // --- fake provider write path

    function test_fakeCommitSyncRoundTrip() {
        var opts = { data: { notes: [], labels: [] } }
        var s = Fake.createSession(account, "s", opts)
        var state = s.createState()
        var note = s.commit(state, { id: "", type: "NOTE", title: "Hi", items: [] })
        compare(s.notes(state)[0].title, "Hi")
        compare(s.pending(state), 1)
        var done = false
        s.sync(state).then(function () { done = true })
        tryVerify(function () { return done })
        compare(opts.data.notes.length, 1)
        compare(s.pending(state), 0)
        s.remove(state, note.id)
        done = false
        s.sync(state).then(function () { done = true })
        tryVerify(function () { return done })
        compare(opts.data.notes.length, 0)
    }

    function test_keepSessionReordersANote() {
        var log = []
        var s = keepSession(echoServer(log))
        var state = s.createState()
        var a = s.commit(state, noteSnapshot("A"))
        var b = s.commit(state, noteSnapshot("B"))          // created later: above A
        var done = false
        s.sync(state).then(function () { done = true })
        tryVerify(function () { return done })
        compare(s.notes(state).map(function (n) { return n.title }).join(), "B,A")
        verify(s.reorder(state, a.id, b.order + 5000))
        compare(s.notes(state).map(function (n) { return n.title }).join(), "A,B")
        compare(s.pending(state), 1)
        done = false
        s.sync(state).then(function () { done = true })
        tryVerify(function () { return done })
        compare(s.pending(state), 0)
        compare(log[log.length - 1].nodes.length, 1)        // only the moved note was sent
        compare(s.notes(state)[0].title, "A")
    }

    function test_fakeReorderRoundTrip() {
        var opts = { data: { notes: [{ id: "a", title: "A", order: 10 }, { id: "b", title: "B", order: 20 }], labels: [] } }
        var s = Fake.createSession(account, "s", opts)
        var state = s.createState()
        var done = false
        s.sync(state).then(function () { done = true })
        tryVerify(function () { return done })
        verify(s.reorder(state, "a", 30))
        verify(!s.reorder(state, "a", 30))
        compare(s.pending(state), 1)
        done = false
        s.sync(state).then(function () { done = true })
        tryVerify(function () { return done })
        compare(opts.data.notes.filter(function (n) { return n.id === "a" })[0].order, 30)
    }

    function test_keepSessionSendsLabelEditsAndClearsTheQueue() {
        var sent = []
        var s = Keep.createSession(account, "master", {
            performOAuth: oauthOk({ n: 0 }),
            transport: function (token, body) {
                sent.push(body)
                // The server echoes the complete label list; a deleted label is absent.
                var labels = (body.userInfo ? body.userInfo.labels : []).filter(function (l) {
                    return l.timestamps.deleted.indexOf("1970") === 0
                })
                return Promise.resolve({ toVersion: "v1", truncated: false, userInfo: { labels: labels } })
            }
        })
        verify(Keep.capabilities.labelEdit)
        compare(Contract.validateSession(s, Keep.capabilities).join(), "")
        var state = s.createState()
        var made = s.createLabel(state, "Ideas")
        verify(made !== null)
        compare(s.pending(state), 1)
        compare(s.labels(state)[0].name, "Ideas")
        var done = false
        s.sync(state).then(function () { done = true })
        tryVerify(function () { return done })
        compare(sent[0].userInfo.labels[0].mainId, made.id)
        compare(s.pending(state), 0)
        compare(s.labels(state)[0].name, "Ideas")

        // Rename, then delete: each goes out once and the label is gone afterwards.
        verify(s.renameLabel(state, made.id, "Plans"))
        done = false
        s.sync(state).then(function () { done = true })
        tryVerify(function () { return done })
        compare(sent[1].userInfo.labels[0].name, "Plans")
        verify(s.deleteLabel(state, made.id))
        compare(s.labels(state).length, 0)
        done = false
        s.sync(state).then(function () { done = true })
        tryVerify(function () { return done })
        verify(sent[2].userInfo.labels[0].timestamps.deleted.indexOf("1970") !== 0)
        compare(s.pending(state), 0)
        compare(s.labels(state).length, 0)
    }
}
