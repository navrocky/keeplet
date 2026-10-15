.pragma library
.import "gauth.js" as GAuth
.import "keepapi.js" as KeepApi
.import "nodes.js" as Nodes
.import "../../core/errors.js" as Errors

// Google Keep provider (private mobile API). Implements the contract in docs/providers.md.

var id = "keep"
var name = "Google Keep"
var icon = "knotes"

var capabilities = {
    labels: "multi", colors: true, checklists: true, nestedItems: true,
    pinned: true, archive: true, trash: true, images: true,
    offlineEdit: false // flips to true with the write path (stage C)
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

    function run(state, dirty, retried) {
        return authToken().then(function (t) {
            return KeepApi.sync(t, state, dirty, options.transport)
        }).catch(function (e) {
            if (e && e.kind === "Unauthorized" && !retried) {
                token = ""
                return run(state, dirty, true)
            }
            throw e
        })
    }

    return {
        createState: Nodes.createState,

        restoreState: function (obj) {
            if (obj && typeof obj.nodes === "object" && typeof obj.labels === "object")
                return { version: obj.version || "", nodes: obj.nodes, labels: obj.labels }
            return null
        },

        // Mutates and resolves with state; rejects with a ProviderError.
        sync: function (state, dirty) {
            return run(state, dirty || [], false).catch(function (e) { throw _mapError(e) })
        },

        notes: function (state) {
            return Nodes.buildNotes(state).map(function (n) {
                n.order = n.sortValue
                return n
            })
        },

        labels: function (state) {
            return Nodes.buildLabels(state)
        }
    }
}
