import QtQuick
import QtTest
import "../package/contents/ui/services" as Services
import "../package/contents/ui/viewmodel" as VM

TestCase {
    id: tc
    name: "UpdateViewModel"
    when: windowShown

    readonly property real day: 24 * 3600 * 1000

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
    Component { id: svcComp; Services.UpdateCheck {} }
    Component { id: vmComp; VM.UpdateViewModel {} }

    // c.clock is the fake time, c.store the version the fake store answers ("" = unreachable).
    function make(opts) {
        opts = opts || {}
        var c = { clock: 10 * day, store: opts.store !== undefined ? opts.store : "1.0.0", fetches: 0 }
        c.db = opts.db || dbComp.createObject(tc, { data: {} })
        c.svc = svcComp.createObject(tc, {
            db: c.db, enabled: opts.enabled !== undefined ? opts.enabled : true,
            fetch: function () { c.fetches++; return Promise.resolve(c.store) },
            now: function () { return c.clock }
        })
        c.vm = vmComp.createObject(tc, { service: c.svc, currentVersion: opts.current || "0.9.0" })
        wait(10)
        return c
    }

    function test_newerVersionIsOffered() {
        var c = make()
        compare(c.fetches, 1)
        compare(c.vm.latestVersion, "1.0.0")
        verify(c.vm.available)
        compare(c.db.data["updates/latest"], "1.0.0")
    }

    function test_sameOrDevVersionIsNotOffered() {
        verify(!make({ current: "1.0.0" }).vm.available)
        verify(!make({ current: "0.0.0-dev.4+abc1234" }).vm.available)
    }

    function test_atMostOnceADayForAllInstances() {
        var a = make()
        var b = make({ db: a.db })
        compare(b.fetches, 0)
        verify(b.vm.available)       // what the first instance found
        b.clock += day
        b.svc.check()
        wait(10)
        compare(b.fetches, 1)
    }

    function test_failedCheckIsRetried() {
        var c = make({ store: "" })
        verify(!c.vm.available)
        c.store = "1.0.0"
        c.svc.check()
        wait(10)
        compare(c.fetches, 2)
        verify(c.vm.available)
    }

    function test_dismissHidesUntilANewerVersion() {
        var c = make()
        c.vm.dismiss()
        verify(!c.vm.available)
        compare(c.db.data["updates/dismissed"], "1.0.0")
        verify(!make({ db: c.db }).vm.available)
        c.store = "1.1.0"
        c.clock += day
        c.svc.check()
        wait(10)
        verify(c.vm.available)
    }

    function test_disabledNeverAsks() {
        var c = make({ enabled: false })
        compare(c.fetches, 0)
        verify(!c.vm.available)
        c.svc.enabled = true
        wait(10)
        compare(c.fetches, 1)
        verify(c.vm.available)
    }

    function test_markInstalled() {
        var c = make()
        verify(!c.vm.installed)
        c.vm.markInstalled()
        verify(c.vm.installed)
        verify(c.vm.available)
    }
}
