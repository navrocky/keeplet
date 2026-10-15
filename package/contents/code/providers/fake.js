.pragma library
.import "../core/notes.js" as Notes
.import "../core/errors.js" as Errors

// In-memory provider for tests and UI previews. Not registered in the release registry.
// createSession's options: {data: {notes: [...], labels: [...]}, fail: ProviderError|null}
// are read on every call, so a test can change them between syncs.

var id = "fake"
var name = "Fake"
var icon = "applications-development"

var capabilities = {
    labels: "multi", colors: ["DEFAULT", "RED", "BLUE"], checklists: true, nestedItems: false,
    pinned: true, archive: true, trash: true, images: false, write: true, offlineEdit: true
}

var credentialFields = [{ key: "name", label: "Name", secret: false }]

function signIn(creds) {
    if (creds.name === "bad")
        return Promise.reject(new Errors.ProviderError("badCredentials"))
    return Promise.resolve({ accountId: creds.name, displayName: creds.name, secret: "fake-secret", meta: {} })
}

var _counter = 0

function createSession(account, secret, options) {
    options = options || {}

    function upsert(list, note) {
        for (var i = 0; i < list.length; i++) {
            if (list[i].id === note.id) {
                list[i] = note
                return
            }
        }
        list.push(note)
    }

    return {
        createState: function () { return { version: "", notes: [], labels: [], pending: [] } },

        restoreState: function (obj) {
            if (!obj || !Array.isArray(obj.notes) || !Array.isArray(obj.labels))
                return null
            obj.pending = Array.isArray(obj.pending) ? obj.pending : []
            return obj
        },

        // Applies queued edits to the "server" (options.data), then pulls it. A failure keeps the queue.
        sync: function (state) {
            if (options.fail)
                return Promise.reject(options.fail)
            var data = options.data || { notes: [], labels: [] }
            ;(state.pending || []).forEach(function (op) {
                if (op.kind === "remove")
                    data.notes = data.notes.filter(function (n) { return n.id !== op.id })
                else
                    upsert(data.notes, JSON.parse(JSON.stringify(op.note)))
            })
            state.pending = []
            state.notes = JSON.parse(JSON.stringify(data.notes))
            state.labels = JSON.parse(JSON.stringify(data.labels || []))
            state.version = String(Number(state.version || 0) + 1)
            return Promise.resolve(state)
        },

        notes: function (state) {
            return state.notes.map(function (n) { return Notes.makeNote(n) })
        },

        labels: function (state) {
            return state.labels.map(function (l) { return { id: l.id, name: l.name } })
        },

        commit: function (state, snapshot) {
            var existing = null
            state.notes.forEach(function (n) { if (n.id === snapshot.id) existing = n })
            var note = Notes.makeNote(snapshot)
            // Without an explicit position a note keeps the one it has.
            if (snapshot.order === undefined)
                note.order = existing && existing.order !== undefined ? existing.order : 0
            if (!note.id) {
                _counter += 1
                note.id = "fake-new-" + _counter
            }
            note.items = note.items.map(function (it, i) {
                return { id: it.id || note.id + ".i" + i, text: it.text, checked: !!it.checked, indent: it.indent || 0 }
            })
            note.updated = "2026-12-31T00:00:00Z"
            upsert(state.notes, note)
            state.pending.push({ kind: "save", note: note })
            return Notes.makeNote(note)
        },

        remove: function (state, noteId) {
            state.notes = state.notes.filter(function (n) { return n.id !== noteId })
            state.pending.push({ kind: "remove", id: noteId })
        },

        pending: function (state) { return state.pending.length }
    }
}
