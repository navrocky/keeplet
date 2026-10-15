import QtQuick
import QtTest
import "../package/contents/code/core/history.js" as History

TestCase {
    name: "History"

    // Applies a change like an owner would: record the old value, switch to the new one.
    function change(h, state, next, key, now) {
        History.record(h, state.value, key, now)
        state.value = next
    }

    function test_emptyHistoryHasNothingToDo() {
        var h = History.create()
        verify(!History.canUndo(h))
        verify(!History.canRedo(h))
        verify(History.undo(h, "x") === null)
        verify(History.redo(h, "x") === null)
    }

    function test_undoAndRedoWalkThroughDiscreteChanges() {
        var h = History.create()
        var s = { value: "a" }
        change(h, s, "b", "", 0)
        change(h, s, "c", "", 1)
        verify(History.canUndo(h))
        s.value = History.undo(h, s.value)
        compare(s.value, "b")
        s.value = History.undo(h, s.value)
        compare(s.value, "a")
        verify(!History.canUndo(h))
        verify(History.canRedo(h))
        s.value = History.redo(h, s.value)
        compare(s.value, "b")
        s.value = History.redo(h, s.value)
        compare(s.value, "c")
        verify(!History.canRedo(h))
    }

    function test_typingWithinTheWindowIsOneStep() {
        var h = History.create({ window: 500 })
        var s = { value: "" }
        change(h, s, "h", "text", 0)
        change(h, s, "he", "text", 100)
        change(h, s, "hel", "text", 250)
        change(h, s, "hell", "text", 700)    // 450 ms after the previous keystroke: still the same run
        compare(h.past.length, 1)
        s.value = History.undo(h, s.value)
        compare(s.value, "")
    }

    function test_pauseStartsANewStep() {
        var h = History.create({ window: 500 })
        var s = { value: "" }
        change(h, s, "a", "text", 0)
        change(h, s, "ab", "text", 2000)     // paused longer than the window
        compare(h.past.length, 2)
        s.value = History.undo(h, s.value)
        compare(s.value, "a")
    }

    function test_differentKeysAreSeparateSteps() {
        var h = History.create()
        var s = { value: "" }
        change(h, s, "t", "title", 0)
        change(h, s, "tb", "body", 10)
        compare(h.past.length, 2)
    }

    function test_discreteChangeBreaksATypingRun() {
        var h = History.create({ window: 500 })
        var s = { value: "" }
        change(h, s, "a", "text", 0)
        change(h, s, "A", "", 10)            // e.g. a color change
        change(h, s, "Ab", "text", 20)
        compare(h.past.length, 3)
    }

    function test_newChangeDropsTheRedoBranch() {
        var h = History.create()
        var s = { value: "a" }
        change(h, s, "b", "", 0)
        s.value = History.undo(h, s.value)
        verify(History.canRedo(h))
        change(h, s, "c", "", 5)
        verify(!History.canRedo(h))
    }

    function test_undoBreaksCoalescing() {
        var h = History.create({ window: 5000 })
        var s = { value: "" }
        change(h, s, "a", "text", 0)
        s.value = History.undo(h, s.value)
        change(h, s, "b", "text", 10)        // same key and time window, but after an undo
        compare(h.past.length, 1)
        s.value = History.undo(h, s.value)
        compare(s.value, "")
    }

    function test_limitDropsTheOldestSteps() {
        var h = History.create({ limit: 3 })
        var s = { value: 0 }
        for (var i = 1; i <= 6; i++)
            change(h, s, i, "", i)
        compare(h.past.length, 3)
        var back = []
        while (History.canUndo(h)) {
            s.value = History.undo(h, s.value)
            back.push(s.value)
        }
        compare(back.join(), "5,4,3")
    }

    function test_clear() {
        var h = History.create()
        var s = { value: "a" }
        change(h, s, "b", "", 0)
        History.clear(h)
        verify(!History.canUndo(h))
        verify(!History.canRedo(h))
    }
}
