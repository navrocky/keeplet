import QtQuick
import QtTest
import "../package/contents/ui/services" as Services

// LocalDb against the real QtQuick.LocalStorage: asynchronous, ordered, coalescing.
TestCase {
    id: tc
    name: "LocalDb"
    when: windowShown

    Component { id: dbComp; Services.LocalDb {} }
    readonly property string ns: "test-localdb"

    function got(promise) {
        var box = { done: false, value: undefined }
        promise.then(function (v) { box.done = true; box.value = v })
        tryVerify(function () { return box.done })
        return box.value
    }

    function cleanup() {
        var db = dbComp.createObject(tc)
        got(db.remove(ns, "a"))
        got(db.remove(ns, "b"))
        db.destroy()
    }

    function test_callsReturnAtOnceAndResolveLater() {
        var db = dbComp.createObject(tc)
        var p = db.set(ns, "a", "1")
        verify(p instanceof Promise)
        compare(db.pending, 1)                    // nothing was written inside the call
        got(p)
        compare(db.pending, 0)
        compare(got(db.get(ns, "a")), "1")
        db.destroy()
    }

    function test_aReadSeesEarlierWrites() {
        var db = dbComp.createObject(tc)
        db.set(ns, "a", "x")
        compare(got(db.get(ns, "a")), "x")        // answered from the queue
        db.remove(ns, "a")
        compare(got(db.get(ns, "a")), "")
        db.destroy()
    }

    function test_writesToOneKeyAreCoalesced() {
        var db = dbComp.createObject(tc)
        var first = db.set(ns, "a", "1")
        db.set(ns, "a", "2")
        var last = db.set(ns, "a", "3")
        compare(db.pending, 1)                    // one write for three calls
        got(first)
        got(last)
        compare(got(db.get(ns, "a")), "3")
        db.destroy()
    }

    function test_operationsRunOnePerEventLoopTurn() {
        var db = dbComp.createObject(tc)
        db.set(ns, "a", "1")
        db.set(ns, "b", "2")
        var seen = []
        db.pendingChanged.connect(function () { seen.push(db.pending) })
        compare(db.pending, 2)
        tryCompare(db, "pending", 0)
        compare(seen.join(), "1,0")               // one operation per turn: 2 -> 1 -> 0, never 2 -> 0
        db.destroy()
    }

    function test_drainWritesEverythingAtOnce() {
        var db = dbComp.createObject(tc)
        db.set(ns, "a", "1")
        db.set(ns, "b", "2")
        db.drain()
        compare(db.pending, 0)
        var other = dbComp.createObject(tc)       // a second connection sees the stored values
        compare(got(other.get(ns, "a")), "1")
        compare(got(other.get(ns, "b")), "2")
        db.destroy()
        other.destroy()
    }

    function test_destroyingTheStoreWritesWhatIsQueued() {
        var db = dbComp.createObject(tc)
        db.set(ns, "a", "kept")
        db.destroy()
        wait(20)
        var other = dbComp.createObject(tc)
        compare(got(other.get(ns, "a")), "kept")
        other.destroy()
    }
}
