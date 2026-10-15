import QtQuick
import QtTest
import "../package/contents/code/keepapi.js" as KeepApi
import "../package/contents/code/nodes.js" as Nodes

TestCase {
    name: "KeepApi"

    when: windowShown

    function page(version, truncated, ids) {
        return {
            toVersion: version,
            truncated: truncated,
            nodes: ids.map(function (id) {
                return { id: id, parentId: "root", type: "NOTE",
                         timestamps: { deleted: "1970-01-01T00:00:00.000000Z" } }
            })
        }
    }

    function fakeServer(pages, log) {
        var i = 0
        return function (token, body) {
            log.push({ token: token, body: body })
            return Promise.resolve(pages[i++])
        }
    }

    function test_buildRequest() {
        var s = Nodes.createState()
        var r = KeepApi.buildRequest(s, [], "s--1--2")
        verify(r.targetVersion === undefined)
        compare(r.requestHeader.clientSessionId, "s--1--2")
        compare(r.requestHeader.clientPlatform, "ANDROID")
        verify(r.clientTimestamp.indexOf("000Z") === r.clientTimestamp.length - 4)
        s.version = "v9"
        compare(KeepApi.buildRequest(s, [], "x").targetVersion, "v9")
    }

    function test_sessionIdFormat() {
        verify(/^s--\d+--\d{10}$/.test(KeepApi.newSessionId()))
    }

    function test_sync_followsTruncatedPages() {
        var log = []
        var s = Nodes.createState()
        var done = null
        KeepApi.sync("tok", s, [], fakeServer([
            page("v1", true, ["a"]), page("v2", true, ["b"]), page("v3", false, ["c"])
        ], log)).then(function (r) { done = r })
        tryVerify(function () { return done !== null })
        compare(log.length, 3)
        compare(s.version, "v3")
        compare(Object.keys(s.nodes).sort().join(), "a,b,c")
        // Each page continues from the version the server returned.
        verify(log[0].body.targetVersion === undefined)
        compare(log[1].body.targetVersion, "v1")
        compare(log[2].body.targetVersion, "v2")
        compare(log[0].token, "tok")
    }

    function test_sync_sendsDirtyNodesOnlyOnFirstPage() {
        var log = []
        var s = Nodes.createState()
        var done = false
        KeepApi.sync("t", s, [{ id: "x" }], fakeServer([
            page("v1", true, []), page("v2", false, [])
        ], log)).then(function () { done = true })
        tryVerify(function () { return done })
        compare(log[0].body.nodes.length, 1)
        compare(log[1].body.nodes.length, 0)
    }

    function test_sync_fullResyncResetsState() {
        var log = []
        var s = Nodes.createState()
        s.version = "old"
        s.nodes = { stale: { id: "stale" } }
        var done = false
        KeepApi.sync("t", s, [], fakeServer([
            { forceFullResync: true },
            page("fresh", false, ["a"])
        ], log)).then(function () { done = true })
        tryVerify(function () { return done })
        compare(Object.keys(s.nodes).join(), "a")
        compare(s.version, "fresh")
        verify(log[1].body.targetVersion === undefined)
    }

    function test_sync_rejectsRepeatedFullResync() {
        var s = Nodes.createState()
        var err = null
        KeepApi.sync("t", s, [], fakeServer([
            { forceFullResync: true }, { forceFullResync: true }
        ], [])).catch(function (e) { err = e })
        tryVerify(function () { return err !== null })
        compare(err.kind, "Protocol")
    }

    function test_sync_propagatesErrors() {
        var err = null
        KeepApi.sync("t", Nodes.createState(), [], function () {
            return Promise.reject(new KeepApi.KeepApiError("Unauthorized", 401))
        }).catch(function (e) { err = e })
        tryVerify(function () { return err !== null })
        compare(err.kind, "Unauthorized")
    }
}
