.pragma library
.import "../../core/notes.js" as Notes
.import "../keep/nodes.js" as Nodes
.import "../../core/labels.js" as Labels

// Local provider: notes live only on this machine, there is no service and no sign-in. The provider state
// IS the data, so the app must keep it durably (capabilities.persistent) instead of treating it as a cache.
// Implements the contract in docs/providers.md.

var id = "local"
var name = "Local notes"
var icon = "folder"

var capabilities = {
    labels: "multi", colors: Nodes.COLORS, checklists: true, nestedItems: false, convertType: true,
    pinned: true, archive: true, trash: true, images: false,
    write: true, reorder: true, offlineEdit: true,
    labelEdit: true,
    persistent: true  // the state is the only copy: saved at once, never replaced by an empty one
}

// The "account" is just a named notebook.
var credentialFields = [{ key: "name", label: "Account name", secret: false }]

function signIn(creds) {
    var title = String(creds.name || "").trim()
    return Promise.resolve({ accountId: title, displayName: title, secret: "local", meta: {} })
}

var _counter = 0

function _newId(prefix) {
    _counter += 1
    return prefix + Date.now().toString(36) + _counter.toString(36) + Math.floor(Math.random() * 1e6).toString(36)
}

function _now() {
    return new Date().toISOString()
}

function createSession(account, secret, options) {
    options = options || {}
    var now = options.now || _now

    function find(state, noteId) {
        for (var i = 0; i < state.notes.length; i++) {
            if (state.notes[i].id === noteId)
                return state.notes[i]
        }
        return null
    }

    // New notes go on top: one above the highest position in use.
    function topOrder(state) {
        var top = 0
        state.notes.forEach(function (n) { if (n.order > top) top = n.order })
        return top + 1
    }

    // Labels are created by name; the same name reuses the label.
    function resolveLabels(state, labels) {
        return (labels || []).map(function (l) {
            var found = null
            var lower = String(l.name).toLowerCase()
            state.labels.forEach(function (x) { if (x.id === l.id || x.name.toLowerCase() === lower) found = x })
            if (!found)
                found = Labels.create(state, l.name, function () { return l.id || _newId("g") })
            if (!found)
                return null
            return { id: found.id, name: found.name }
        }).filter(function (l) { return l !== null })
    }

    return {
        createState: function () { return { version: "1", notes: [], labels: [], pending: [] } },

        restoreState: function (obj) {
            if (!obj || !Array.isArray(obj.notes) || !Array.isArray(obj.labels))
                return null
            obj.pending = []
            return obj
        },

        // Nothing to push or pull.
        sync: function (state) { return Promise.resolve(state) },

        notes: function (state) {
            return state.notes.map(function (n) { return Notes.makeNote(n) })
        },

        labels: function (state) {
            return state.labels.map(function (l) { return { id: l.id, name: l.name } })
        },

        commit: function (state, snapshot) {
            var existing = snapshot.id ? find(state, snapshot.id) : null
            var note = Notes.makeNote(snapshot)
            if (!existing)
                note.id = note.id || _newId("n")
            if (snapshot.order === undefined)
                note.order = existing ? existing.order : topOrder(state)
            note.created = existing ? existing.created : now()
            note.updated = now()
            note.labels = resolveLabels(state, note.labels)
            note.items = note.items.map(function (it) {
                return { id: it.id || _newId("i"), text: it.text, checked: !!it.checked, indent: it.indent || 0 }
            })
            if (existing)
                state.notes[state.notes.indexOf(existing)] = note
            else
                state.notes.push(note)
            return Notes.makeNote(note)
        },

        createLabel: function (state, name) {
            return Labels.create(state, name, function () { return _newId("g") })
        },

        renameLabel: function (state, id, name) { return Labels.rename(state, id, name) },

        deleteLabel: function (state, id) { return Labels.remove(state, id) },

        reorder: function (state, noteId, order) {
            var n = find(state, noteId)
            if (!n || n.order === order)
                return false
            n.order = order
            return true
        },

        remove: function (state, noteId) {
            state.notes = state.notes.filter(function (n) { return n.id !== noteId })
        },

        pending: function () { return 0 }
    }
}
