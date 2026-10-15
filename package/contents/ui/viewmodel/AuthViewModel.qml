import QtQuick
import "../../code/gauth.js" as GAuth
import "../services"

// Account state: sign in/out, master token persistence, cached Keep auth token.
QtObject {
    id: auth

    required property var configuration

    readonly property string email: configuration.email
    property bool signedIn: false
    property bool busy: false
    // Last error as a code for the View to translate; empty when fine.
    // "network" | "badToken" | "sessionExpired" | "storage" | "failed"
    property string error: ""
    property string errorDetail: ""
    readonly property alias storage: store.backend

    property string _master: ""
    property string _token: ""
    property real _expiry: 0
    property var _pending: null

    property SecretStore store: SecretStore {
        id: store
        configuration: auth.configuration
    }

    function _fail(e) {
        errorDetail = String(e)
        if (GAuth.isNetworkError(e))
            error = "network"
        else if (e && e.code === "BadAuthentication")
            error = "badToken"
        else
            error = "failed"
    }

    function restore() {
        if (!email)
            return
        busy = true
        store.read(email).then(function (master) {
            _master = master || ""
            signedIn = _master !== ""
        }).catch(function (e) {
            error = "storage"
            errorDetail = String(e)
        }).then(function () {
            busy = false
        })
    }

    function signIn(newEmail, oauthToken) {
        newEmail = newEmail.trim()
        oauthToken = oauthToken.trim()
        busy = true
        error = ""
        var androidId = GAuth.newAndroidId()
        var master
        GAuth.exchangeToken(newEmail, oauthToken, androidId).then(function (m) {
            master = m
            return store.write(newEmail, master)
        }).then(function () {
            configuration.androidId = androidId
            configuration.email = newEmail
            _master = master
            _token = ""
            signedIn = true
            return token()
        }).catch(function (e) {
            _fail(e)
        }).then(function () {
            busy = false
        })
    }

    function signOut() {
        var old = email
        signedIn = false
        _master = ""
        _token = ""
        error = ""
        errorDetail = ""
        configuration.email = ""
        configuration.androidId = ""
        if (old)
            store.remove(old).catch(function (e) { console.warn("Keeplet: removing secret:", e) })
    }

    // Resolves with a valid Keep auth token, refreshing it shortly before expiry.
    function token() {
        if (!signedIn)
            return Promise.reject(new Error("not signed in"))
        if (_token && Date.now() < _expiry - 60 * 1000)
            return Promise.resolve(_token)
        if (_pending)
            return _pending
        _pending = GAuth.performOAuth(email, _master, configuration.androidId).then(function (r) {
            _token = r.token
            _expiry = r.expiry
            _pending = null
            return r.token
        }, function (e) {
            _pending = null
            if (!GAuth.isNetworkError(e)) {
                // Master token revoked or broken: the user has to sign in again.
                signOut()
                error = "sessionExpired"
            }
            throw e
        })
        return _pending
    }

    // Call when Keep answers 401 so the next token() fetches a fresh one.
    function invalidateToken() {
        _token = ""
    }

    Component.onCompleted: restore()
}
