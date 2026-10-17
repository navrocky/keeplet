.pragma library
.import "../../core/util.js" as Util

// Port of gpsoauth (https://github.com/simon-weber/gpsoauth, MIT) as used by gkeepapi.
// See docs/auth.md.

var AUTH_URL = "https://android.clients.google.com/auth"
var CLIENT_SIG = "38918a453d07199354f8b19af05ec6562ced5788"
var KEEP_SCOPES = "oauth2:https://www.googleapis.com/auth/memento https://www.googleapis.com/auth/reminders"
var KEEP_APP = "com.google.android.keep"

// Error from the auth endpoint. code is Google's "Error=" value (e.g. "BadAuthentication"),
// or "Network" when the server could not be reached.
function AuthError(code, status) {
    this.code = code
    this.status = status
    this.message = "auth failed: " + code + (status ? " (HTTP " + status + ")" : "")
}
AuthError.prototype.toString = function () { return this.message }

function isNetworkError(e) {
    return e instanceof AuthError && e.code === "Network"
}

function newAndroidId() {
    var id = ""
    for (var i = 0; i < 16; i++)
        id += Math.floor(Math.random() * 16).toString(16)
    return id
}

function exchangeForm(email, oauthToken, androidId) {
    return {
        accountType: "HOSTED_OR_GOOGLE", Email: email, has_permission: 1,
        add_account: 1, ACCESS_TOKEN: 1, Token: oauthToken, service: "ac2dm",
        source: "android", androidId: androidId, device_country: "us",
        operatorCountry: "us", lang: "en", sdk_version: 17,
        client_sig: CLIENT_SIG, callerSig: CLIENT_SIG, droidguard_results: "dummy123"
    }
}

function oauthForm(email, masterToken, androidId) {
    return {
        accountType: "HOSTED_OR_GOOGLE", Email: email, has_permission: 1,
        EncryptedPasswd: masterToken, service: KEEP_SCOPES, source: "android",
        androidId: androidId, app: KEEP_APP, client_sig: CLIENT_SIG,
        device_country: "us", operatorCountry: "us", lang: "en", sdk_version: 17
    }
}

// Resolves with the parsed key=value response, rejects with AuthError.
function post(form) {
    return new Promise(function (resolve, reject) {
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return
            if (xhr.status === 0)
                return reject(new AuthError("Network", 0))
            var kv = Util.parseKeyValue(xhr.responseText)
            if (xhr.status !== 200 || kv.Error)
                return reject(new AuthError(kv.Error || "UnexpectedResponse", xhr.status))
            resolve(kv)
        }
        xhr.open("POST", AUTH_URL)
        xhr.setRequestHeader("User-Agent", "GoogleAuth/1.4")
        xhr.setRequestHeader("Content-Type", "application/x-www-form-urlencoded")
        xhr.send(Util.formEncode(form))
    })
}

// One-time oauth_token cookie -> long-lived master token and the account e-mail.
// `email` may be empty (browser sign-in does not know it): Google answers with the account's address.
// Resolves with {token, email}.
function exchange(email, oauthToken, androidId) {
    return post(exchangeForm(email, oauthToken, androidId)).then(function (kv) {
        if (!kv.Token)
            throw new AuthError("NoToken", 200)
        return { token: kv.Token, email: kv.Email || "" }
    })
}

function exchangeToken(email, oauthToken, androidId) {
    return exchange(email, oauthToken, androidId).then(function (r) { return r.token })
}

// Master token -> Keep auth token. Resolves with {token, expiry} (expiry in ms since epoch).
function performOAuth(email, masterToken, androidId) {
    return post(oauthForm(email, masterToken, androidId)).then(function (kv) {
        if (!kv.Auth)
            throw new AuthError("NoToken", 200)
        var expiry = kv.Expiry ? Number(kv.Expiry) * 1000 : Date.now() + 3600 * 1000
        return { token: kv.Auth, expiry: expiry }
    })
}
