import QtQuick
import QtTest
import "../package/contents/ui/services" as Services
import "../package/contents/ui/viewmodel" as VM
import "../package/contents/code/core/analytics.js" as GA

TestCase {
    id: tc
    name: "Analytics"
    when: windowShown

    // In-memory stand-in for services/LocalDb.qml.
    Component {
        id: dbComp
        QtObject {
            property var data: ({})
            function get(ns, key) { return Promise.resolve(data[ns + "/" + key] || "") }
            function set(ns, key, v) { data[ns + "/" + key] = v; return Promise.resolve() }
            function remove(ns, key) { delete data[ns + "/" + key]; return Promise.resolve() }
            function drain() {}
        }
    }
    Component { id: svcComp; Services.Analytics {} }
    Component { id: vmComp; VM.AnalyticsViewModel {} }

    function make(stored) {
        var db = dbComp.createObject(tc, { data: stored || {} })
        var sent = []
        var svc = svcComp.createObject(tc, {
            db: db, measurementId: "G-TEST", apiSecret: "secret", batchDelay: 10,
            post: function (url, body) { sent.push({ url: url, body: body }); return Promise.resolve(204) }
        })
        wait(20)
        return { db: db, svc: svc, sent: sent }
    }

    // --- Model
    function test_placeholdersMeanNotConfigured() {
        verify(!GA.configured(GA.MEASUREMENT_ID, GA.API_SECRET))
        verify(!GA.configured("", ""))
        verify(GA.configured("G-X", "s"))
    }

    function test_sanitizeKeepsOnlyAllowedParams() {
        compare(GA.sanitize("nope", {}), null)
        var e = GA.sanitize("sync_error", { provider: "keep", kind: "network", detail: "me@x.com", email: "me@x.com" }, 5)
        compare(e.name, "sync_error")
        compare(JSON.stringify(e.params), JSON.stringify({ provider: "keep", kind: "network" }))
        compare(e.time, 5)
    }

    function test_sanitizeValues() {
        var e = GA.sanitize("app_start", { widget_version: new Array(200).join("x"), accounts: 2, locale: { a: 1 } })
        compare(e.params.widget_version.length, GA.MAX_VALUE)
        compare(e.params.accounts, 2)
        verify(!("locale" in e.params))
        compare(GA.sanitize("note_pin", { pinned: true }).params.pinned, "true")
    }

    function test_payload() {
        var events = []
        for (var i = 0; i < 30; i++)
            events.push(GA.sanitize("search", {}, 1000))
        var p = GA.payload("cid", "sid", events)
        compare(p.client_id, "cid")
        compare(p.events.length, GA.MAX_EVENTS)
        compare(p.events[0].name, "search")
        compare(p.events[0].params.session_id, "sid")
        compare(p.events[0].timestamp_micros, 1000000)
    }

    function test_clientIdIsUuid() {
        verify(/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(GA.newClientId()))
    }

    // --- Service
    function test_nothingSentWithoutConsent() {
        var c = make()
        verify(c.svc.ready)
        compare(c.svc.consent, "")
        c.svc.track("search")
        wait(50)
        compare(c.sent.length, 0)
    }

    function test_nothingSentAfterDecline() {
        var c = make({ "analytics/consent": "no" })
        c.svc.track("search")
        wait(50)
        compare(c.sent.length, 0)
    }

    function test_unconfiguredIsSilent() {
        var db = dbComp.createObject(tc, { data: { "analytics/consent": "yes", "analytics/clientId": "c" } })
        var sent = []
        var svc = svcComp.createObject(tc, { db: db, measurementId: GA.MEASUREMENT_ID, apiSecret: GA.API_SECRET, batchDelay: 10,
                                              post: function (u, b) { sent.push(b); return Promise.resolve(204) } })
        wait(20)
        verify(!svc.enabled)
        svc.track("search")
        wait(50)
        compare(sent.length, 0)
    }

    function test_consentSendsWithClientId() {
        var c = make()
        c.svc.setConsent(true)
        verify(c.svc.enabled)
        var id = c.db.data["analytics/clientId"]
        verify(id)
        c.svc.track("note_create", { type: "LIST", title: "secret" })
        tryCompare(c.sent, "length", 1)
        compare(c.sent[0].url.indexOf("measurement_id=G-TEST"), GA.ENDPOINT.length + 1)
        compare(c.sent[0].body.client_id, id)
        compare(c.sent[0].body.events.map(function (e) { return e.name }).join(), "analytics_opt_in,note_create")
        verify(!("title" in c.sent[0].body.events[1].params))
    }

    function test_revokeForgetsClientId() {
        var c = make({ "analytics/consent": "yes", "analytics/clientId": "old", "analytics/lastHeartbeat": "2026-01-01" })
        verify(c.svc.enabled)
        c.svc.track("search")
        c.svc.setConsent(false)
        wait(50)
        compare(c.sent.length, 0)
        compare(c.db.data["analytics/consent"], "no")
        verify(!("analytics/clientId" in c.db.data))
        verify(!("analytics/lastHeartbeat" in c.db.data))
    }

    function test_revokedElsewhereIsHonored() {
        var c = make({ "analytics/consent": "yes", "analytics/clientId": "c" })
        c.svc.track("search")
        c.db.data["analytics/consent"] = "no"    // another instance or the settings
        wait(50)
        compare(c.sent.length, 0)
        compare(c.svc.consent, "no")
    }

    function test_heartbeatOncePerDay() {
        var c = make({ "analytics/consent": "yes", "analytics/clientId": "c" })
        c.svc.heartbeat({ widget_version: "1.0", accounts: 1 })
        wait(5)
        c.svc.heartbeat({ widget_version: "1.0", accounts: 1 })
        tryCompare(c.sent, "length", 1)
        wait(50)
        compare(c.sent.length, 1)
        compare(c.sent[0].body.events.length, 1)
        compare(c.sent[0].body.events[0].name, "app_start")
        compare(c.db.data["analytics/lastHeartbeat"], GA.day(new Date()))
    }

    // --- ViewModel
    function test_viewModelAsksOnce() {
        var c = make()
        var vm = vmComp.createObject(tc, { service: c.svc })
        verify(vm.available)
        verify(vm.askConsent)
        vm.decline()
        verify(!vm.askConsent)
        verify(!vm.enabled)
        vm.setEnabled(true)
        verify(vm.enabled)
    }
}
