import QtQuick
import QtTest
import "../package/contents/code/providers/contract.js" as Contract
import "../package/contents/code/providers/local/index.js" as Local

TestCase {
    name: "LocalProvider"

    readonly property var account: ({ key: "local:home", providerId: "local", accountId: "home", displayName: "home", meta: {} })

    function session() { return Local.createSession(account, "local", {}) }

    function note(props) {
        var n = { id: "", type: "NOTE", title: "T", text: "", items: [], labels: [] }
        for (var k in props)
            n[k] = props[k]
        return n
    }

    function test_honorsContract() {
        compare(Contract.validate(Local).join(), "")
        compare(Contract.validateSession(session(), Local.capabilities).join(), "")
        verify(Local.capabilities.persistent)
    }

    function test_signInNeedsNoSecretAndNamesTheAccount() {
        var r = null
        Local.signIn({ name: "  Home " }).then(function (x) { r = x })
        tryVerify(function () { return r !== null })
        compare(r.accountId, "Home")
        compare(r.displayName, "Home")
    }

    function test_commitCreatesNoteWithIdAndOrderOnTop() {
        var s = session(), st = s.createState()
        var a = s.commit(st, note({ title: "A" }))
        var b = s.commit(st, note({ title: "B" }))
        verify(a.id !== "" && a.id !== b.id)
        verify(b.order > a.order)
        compare(s.notes(st).length, 2)
        compare(s.pending(st), 0)
    }

    function test_commitUpdatesExistingNoteKeepingOrderAndCreated() {
        var s = session(), st = s.createState()
        var a = s.commit(st, note({ title: "A" }))
        var again = s.commit(st, note({ id: a.id, title: "A2" }))
        compare(s.notes(st).length, 1)
        compare(again.title, "A2")
        compare(again.order, a.order)
        compare(again.created, a.created)
    }

    function test_labelsAreCreatedByNameAndReused() {
        var s = session(), st = s.createState()
        s.commit(st, note({ labels: [{ id: "", name: "Work" }] }))
        s.commit(st, note({ labels: [{ id: "", name: "Work" }, { id: "", name: "Home" }] }))
        compare(s.labels(st).length, 2)
    }

    function test_checklistItemsGetIds() {
        var s = session(), st = s.createState()
        var n = s.commit(st, note({ type: "LIST", items: [{ text: "x", checked: true }, { text: "y" }] }))
        verify(n.items[0].id !== "" && n.items[0].id !== n.items[1].id)
        compare(n.items[0].checked, true)
    }

    function test_reorderAndRemove() {
        var s = session(), st = s.createState()
        var a = s.commit(st, note({}))
        verify(s.reorder(st, a.id, 50))
        verify(!s.reorder(st, a.id, 50))
        compare(s.notes(st)[0].order, 50)
        s.remove(st, a.id)
        compare(s.notes(st).length, 0)
    }

    function test_stateSurvivesJsonRoundTrip() {
        var s = session(), st = s.createState()
        s.commit(st, note({ title: "Keep me", labels: [{ id: "", name: "L" }] }))
        var restored = s.restoreState(JSON.parse(JSON.stringify(st)))
        verify(restored !== null)
        compare(s.notes(restored)[0].title, "Keep me")
        compare(s.restoreState({ nope: 1 }), null)
    }

    function test_syncDoesNotTouchTheData() {
        var s = session(), st = s.createState()
        s.commit(st, note({ title: "A" }))
        var done = false
        s.sync(st).then(function () { done = true })
        tryVerify(function () { return done })
        compare(s.notes(st).length, 1)
    }
}
