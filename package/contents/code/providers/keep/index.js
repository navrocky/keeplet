.pragma library
.import "gauth.js" as GAuth
.import "keepapi.js" as KeepApi
.import "nodes.js" as Nodes
.import "mutations.js" as Mutations
.import "../../core/errors.js" as Errors

// Google Keep provider (private mobile API). Implements the contract in docs/providers.md.

var id = "keep"
var name = "Google Keep"
var icon = "knotes"

var capabilities = {
    labels: "multi", colors: Nodes.COLORS, checklists: true, nestedItems: true,
    pinned: true, archive: true, trash: true, images: true,
    write: true,      // session.commit / remove / pending
    offlineEdit: true // edits are queued locally and sent when the server is reachable
}

var credentialFields = [
    { key: "email", label: "Google e-mail", secret: false },
    { key: "oauthToken", label: "oauth_token", secret: true }
]

// Where the user obtains the one-time oauth_token cookie.
var signInHelpUrl = "https://accounts.google.com/EmbeddedSetup"

function _mapError(e) {
    if (Errors.isProviderError(e))
        return e
    if (GAuth.isNetworkError(e) || (e && e.kind === "Network"))
        return new Errors.ProviderError("network")
    if (e && e.code === "BadAuthentication")
        return new Errors.ProviderError("auth", e.code)
    if (e && e.kind === "Unauthorized")
        return new Errors.ProviderError("unauthorized")
    return new Errors.ProviderError("failed", String(e))
}

// creds: {email, oauthToken}. Resolves with {accountId, displayName, secret, meta}.
function signIn(creds) {
    var email = String(creds.email || "").trim()
    var oauthToken = String(creds.oauthToken || "").trim()
    var androidId = GAuth.newAndroidId()
    return GAuth.exchangeToken(email, oauthToken, androidId).then(function (master) {
        return { accountId: email, displayName: email, secret: master, meta: { androidId: androidId } }
    }, function (e) {
        var mapped = _mapError(e)
        // Here "auth" means the one-time token was refused, not that a session expired.
        throw mapped.kind === "auth" ? new Errors.ProviderError("badCredentials") : mapped
    })
}

// options (tests): {transport, performOAuth, now}
function createSession(account, secret, options) {
    options = options || {}
    var email = account.accountId
    var androidId = (account.meta && account.meta.androidId) || ""
    var now = options.now || Date.now
    var performOAuth = options.performOAuth || GAuth.performOAuth
    var token = ""
    var expiry = 0
    var pending = null

    function authToken() {
        if (token && now() < expiry - 60 * 1000)
            return Promise.resolve(token)
        if (pending)
            return pending
        pending = performOAuth(email, secret, androidId).then(function (r) {
            token = r.token
            expiry = r.expiry
            pending = null
            return token
        }, function (e) {
            pending = null
            throw e
        })
        return pending
    }

    function run(state, dirty, retried, syncOptions) {
        return authToken().then(function (t) {
            return KeepApi.sync(t, state, dirty, options.transport, syncOptions)
        }).catch(function (e) {
            if (e && e.kind === "Unauthorized" && !retried) {
                token = ""
                return run(state, dirty, true, syncOptions)
            }
            throw e
        })
    }

    function normalized(n) {
        n.order = n.sortValue
        return n
    }

    return {
        createState: Nodes.createState,

        restoreState: function (obj) {
            if (obj && typeof obj.nodes === "object" && typeof obj.labels === "object") {
                return Nodes.normalizeState({
                    version: obj.version || "", nodes: obj.nodes, labels: obj.labels,
                    dirty: obj.dirty, rev: obj.rev
                })
            }
            return null
        },

        // Pushes the queue of local edits and pulls changes. Mutates and resolves with state; rejects with a
        // ProviderError and keeps the queue, so edits made offline are sent on a later attempt.
        sync: function (state) {
            Nodes.normalizeState(state)
            var pending = []
            var sentRev = {}
            Object.keys(state.dirty).forEach(function (id) {
                pending.push(state.dirty[id].node)
                sentRev[id] = state.dirty[id].rev
            })
            // A node edited while the request was in flight keeps its newer local version.
            var skip = function (id) {
                var d = state.dirty[id]
                return !!d && sentRev[id] !== d.rev
            }
            return run(state, pending, false, { skip: skip }).then(function () {
                Object.keys(sentRev).forEach(function (id) {
                    var d = state.dirty[id]
                    if (d && d.rev === sentRev[id])
                        delete state.dirty[id]
                })
                // Tombstones of notes deleted here have served their purpose.
                Object.keys(state.nodes).forEach(function (id) {
                    if (Nodes.isDeleted(state.nodes[id]) && !state.dirty[id])
                        delete state.nodes[id]
                })
                return state
            }).catch(function (e) { throw _mapError(e) })
        },

        notes: function (state) {
            return Nodes.buildNotes(state).map(normalized)
        },

        labels: function (state) {
            return Nodes.buildLabels(state)
        },

        // Applies an edited (or new, with an empty id) note locally and queues it. Returns the note as stored,
        // including the ids generated for new notes and items.
        commit: function (state, snapshot) {
            Nodes.normalizeState(state)
            var id = Mutations.commit(state, snapshot)
            var note = Nodes.buildNote(state, id)
            return note ? normalized(note) : null
        },

        // Deletes a note for good (queued like any edit).
        remove: function (state, noteId) {
            Nodes.normalizeState(state)
            Mutations.remove(state, noteId)
        },

        // Number of local edits not yet accepted by the server.
        pending: function (state) {
            return Nodes.pendingCount(state)
        }
    }
}
