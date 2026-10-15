import QtQuick
import QtTest
import "../package/contents/code/providers/contract.js" as Contract
import "../package/contents/code/providers/registry.js" as Registry
import "../package/contents/code/providers/fake.js" as Fake
import "../package/contents/code/providers/keep/index.js" as Keep
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
        compare(Contract.validateSession(Keep.createSession(account, "master", {})).join("; "), "")
    }

    function test_fakeProviderMeetsContract() {
        compare(Contract.validate(Fake).join("; "), "")
        compare(Contract.validateSession(Fake.createSession(account, "s", {})).join("; "), "")
    }

    function test_contractReportsProblems() {
        var problems = Contract.validate({ id: "x", name: "X", icon: "i", capabilities: { labels: "weird" }, credentialFields: [] })
        verify(problems.length >= 4)
        verify(problems.some(function (p) { return p.indexOf("labels must be one of") >= 0 }))
        verify(Contract.validate(null).length > 0)
    }

    function test_registryListsKeep() {
        verify(Registry.get("keep") !== null)
        compare(Registry.get("keep").name, "Google Keep")
        compare(Registry.get("nope"), null)
        compare(Registry.list().length, 1)
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
}
