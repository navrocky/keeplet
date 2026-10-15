.pragma library

// Undo/redo history of snapshots (plain JSON-able values), independent of what they describe.
//
// The owner keeps the *current* value and calls record(h, before, key, now) with a copy of the value as it was
// before each change. undo/redo take the current value and return the one to switch to (or null).
// Changes with the same non-empty `key` that follow each other within `window` ms are coalesced into one step,
// so typing a word is undone at once, while discrete actions (empty key) are separate steps.

function create(options) {
    options = options || {}
    return {
        past: [],            // older values, last = most recent
        future: [],          // values undone, last = next to redo
        limit: options.limit || 100,
        window: options.window === undefined ? 800 : options.window,
        lastKey: "",
        lastTime: 0
    }
}

function record(h, before, key, now) {
    var k = key || ""
    var coalesce = k !== "" && k === h.lastKey && (now - h.lastTime) < h.window
    h.lastKey = k
    h.lastTime = now
    if (!coalesce) {
        h.past.push(before)
        if (h.past.length > h.limit)
            h.past.shift()
    }
    h.future = []
}

function canUndo(h) { return h.past.length > 0 }
function canRedo(h) { return h.future.length > 0 }

function undo(h, current) {
    if (h.past.length === 0)
        return null
    h.future.push(current)
    h.lastKey = ""
    return h.past.pop()
}

function redo(h, current) {
    if (h.future.length === 0)
        return null
    h.past.push(current)
    h.lastKey = ""
    return h.future.pop()
}

function clear(h) {
    h.past = []
    h.future = []
    h.lastKey = ""
    h.lastTime = 0
}
