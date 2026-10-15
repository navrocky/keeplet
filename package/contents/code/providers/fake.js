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
    pinned: true, archive: true, trash: true, images: false, offlineEdit: false
}

var credentialFields = [{ key: "name", label: "Name", secret: false }]

function signIn(creds) {
    if (creds.name === "bad")
        return Promise.reject(new Errors.ProviderError("badCredentials"))
    return Promise.resolve({ accountId: creds.name, displayName: creds.name, secret: "fake-secret", meta: {} })
}

function createSession(account, secret, options) {
    options = options || {}
    return {
        createState: function () { return { version: "", notes: [], labels: [] } },

        restoreState: function (obj) {
            return obj && Array.isArray(obj.notes) && Array.isArray(obj.labels) ? obj : null
        },

        sync: function (state, dirty) {
            if (options.fail)
                return Promise.reject(options.fail)
            var data = options.data || { notes: [], labels: [] }
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
        }
    }
}
