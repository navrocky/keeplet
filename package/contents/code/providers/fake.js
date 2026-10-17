.pragma library
.import "../core/notes.js" as Notes
.import "../core/errors.js" as Errors
.import "../core/labels.js" as Labels

// In-memory provider for tests and UI previews. Not registered in the release registry.
// createSession's options: {data: {notes: [...], labels: [...]}, fail: ProviderError|null}
// are read on every call, so a test can change them between syncs.

var id = "fake"
var name = "Fake"
var icon = "applications-development"

var capabilities = {
    labels: "multi", colors: ["DEFAULT", "RED", "BLUE"], checklists: true, nestedItems: false, convertType: true,
    pinned: true, archive: true, trash: true, images: false, write: true, reorder: true, offlineEdit: true, persistent: false, labelEdit: true
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
                if (op.kind === "label") {
                    if (op.op === "create")
                        data.labels.push({ id: op.id, name: op.name })
                    else if (op.op === "rename")
                        Labels.rename(data, op.id, op.name)
                    else
                        Labels.remove(data, op.id)
                } else if (op.kind === "remove")
                    data.notes = data.notes.filter(function (n) { return n.id !== op.id })
                else if (op.kind === "order")
                    data.notes.forEach(function (n) { if (n.id === op.id) n.order = op.order })
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

        note: function (state, id) {
            var found = state.notes.filter(function (n) { return n.id === id })[0]
            return found ? Notes.makeNote(found) : null
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

        createLabel: function (state, name) {
            _counter += 1
            var made = Labels.create(state, name, function () { return "fake-label-" + _counter })
            if (made)
                state.pending.push({ kind: "label", op: "create", id: made.id, name: made.name })
            return made
        },

        renameLabel: function (state, id, name) {
            if (!Labels.rename(state, id, name))
                return false
            state.pending.push({ kind: "label", op: "rename", id: id, name: Labels.cleanName(name) })
            return true
        },

        deleteLabel: function (state, id) {
            if (!Labels.remove(state, id))
                return false
            state.pending.push({ kind: "label", op: "delete", id: id })
            return true
        },

        reorder: function (state, noteId, order) {
            var done = false
            state.notes.forEach(function (n) {
                if (n.id === noteId && n.order !== order) {
                    n.order = order
                    state.pending.push({ kind: "order", id: noteId, order: order })
                    done = true
                }
            })
            return done
        },

        remove: function (state, noteId) {
            state.notes = state.notes.filter(function (n) { return n.id !== noteId })
            state.pending.push({ kind: "remove", id: noteId })
        },

        pending: function (state) { return state.pending.length }
    }
}
