// Stage 0 spike A: can pure QML XHR do the gpsoauth chain and talk to Keep?
// Run via spike/run-auth.sh, not directly.
import QtQuick

Item {
    readonly property string authUrl: "https://android.clients.google.com/auth"
    readonly property string keepUrl: "https://www.googleapis.com/notes/v1/changes"
    readonly property string clientSig: "38918a453d07199354f8b19af05ec6562ced5788"
    readonly property string scopes: "oauth2:https://www.googleapis.com/auth/memento https://www.googleapis.com/auth/reminders"

    property string statePath: Qt.application.arguments[Qt.application.arguments.length - 1]
    property var st: ({})

    function log(step, msg) { console.log("[" + step + "] " + msg) }
    function mask(s) { return s ? s.substr(0, 8) + "…(" + s.length + ")" : "<empty>" }

    function readFile(path) {
        var x = new XMLHttpRequest()
        x.open("GET", "file://" + path, false)
        x.send()
        return x.responseText
    }
    // Async on purpose: a synchronous file:// PUT truncates the file and writes nothing (Qt 6.11).
    function writeFile(path, text, cb) {
        var x = new XMLHttpRequest()
        x.onreadystatechange = function () {
            if (x.readyState !== 4) return
            if (readFile(path) !== text) {
                log("state", "FAILED to write " + path)
                return finish(false)
            }
            cb()
        }
        x.open("PUT", "file://" + path)
        x.send(text)
    }

    function form(data) {
        var parts = []
        for (var k in data)
            parts.push(encodeURIComponent(k) + "=" + encodeURIComponent(data[k]))
        return parts.join("&")
    }
    function parseKV(text) {
        var res = {}
        text.split("\n").forEach(function (line) {
            var i = line.indexOf("=")
            if (i > 0) res[line.substr(0, i)] = line.substr(i + 1)
        })
        return res
    }

    function authRequest(step, data, cb) {
        var x = new XMLHttpRequest()
        x.onreadystatechange = function () {
            if (x.readyState !== 4) return
            var kv = parseKV(x.responseText)
            log(step, "HTTP " + x.status + ", keys: " + Object.keys(kv).join(","))
            if (kv.Error) log(step, "Error=" + kv.Error)
            cb(x.status, kv)
        }
        x.open("POST", authUrl)
        x.setRequestHeader("User-Agent", "GoogleAuth/1.4")
        x.setRequestHeader("Content-Type", "application/x-www-form-urlencoded")
        x.send(form(data))
    }

    // gpsoauth.exchange_token
    function exchangeToken(cb) {
        authRequest("exchange", {
            accountType: "HOSTED_OR_GOOGLE", Email: st.email, has_permission: 1,
            add_account: 1, ACCESS_TOKEN: 1, Token: st.oauth_token, service: "ac2dm",
            source: "android", androidId: st.android_id, device_country: "us",
            operatorCountry: "us", lang: "en", sdk_version: 17,
            client_sig: clientSig, callerSig: clientSig, droidguard_results: "dummy123"
        }, function (status, kv) {
            if (!kv.Token) return finish(false)
            st.master_token = kv.Token
            delete st.oauth_token
            writeFile(statePath, JSON.stringify(st), function () {
                log("exchange", "master token " + mask(st.master_token) + " saved")
                cb()
            })
        })
    }

    // gpsoauth.perform_oauth
    function performOAuth(cb) {
        authRequest("oauth", {
            accountType: "HOSTED_OR_GOOGLE", Email: st.email, has_permission: 1,
            EncryptedPasswd: st.master_token, service: scopes, source: "android",
            androidId: st.android_id, app: "com.google.android.keep", client_sig: clientSig,
            device_country: "us", operatorCountry: "us", lang: "en", sdk_version: 17
        }, function (status, kv) {
            if (!kv.Auth) return finish(false)
            log("oauth", "auth token " + mask(kv.Auth) + ", expiry " + new Date(kv.Expiry * 1000))
            cb(kv.Auth)
        })
    }

    function changes(auth) {
        var body = {
            nodes: [],
            clientTimestamp: new Date().toISOString().replace("Z", "000Z"),
            requestHeader: {
                clientSessionId: "s--" + Date.now() + "--" + Math.floor(1e9 + Math.random() * 9e9),
                clientPlatform: "ANDROID",
                clientVersion: { major: "9", minor: "9", build: "9", revision: "9" },
                capabilities: ["NC", "PI", "LB", "AN", "SH", "DR", "TR", "IN", "SNB", "MI", "CO"]
                    .map(function (t) { return { type: t } })
            }
        }
        var x = new XMLHttpRequest()
        x.onreadystatechange = function () {
            if (x.readyState !== 4) return
            log("changes", "HTTP " + x.status)
            if (x.status !== 200) {
                log("changes", x.responseText.substr(0, 500))
                return finish(false)
            }
            var r = JSON.parse(x.responseText)
            var nodes = r.nodes || []
            var notes = nodes.filter(function (n) { return n.parentId === "root" })
            log("changes", "toVersion=" + r.toVersion + " truncated=" + r.truncated
                + " nodes=" + nodes.length + " top-level=" + notes.length
                + " labels=" + ((r.userInfo && r.userInfo.labels) || []).length)
            notes.slice(0, 5).forEach(function (n) {
                log("changes", "  " + n.type + " '" + (n.title || "").substr(0, 40) + "'")
            })
            finish(true)
        }
        x.open("POST", keepUrl)
        x.setRequestHeader("Authorization", "OAuth " + auth)
        x.setRequestHeader("Content-Type", "application/json")
        x.send(JSON.stringify(body))
    }

    function finish(ok) {
        log("result", ok ? "OK: pure QML works end-to-end" : "FAILED")
        Qt.exit(ok ? 0 : 1)
    }

    Component.onCompleted: {
        st = JSON.parse(readFile(statePath))
        log("init", "email=" + st.email + " androidId=" + st.android_id
            + " master=" + mask(st.master_token) + " oauth_token=" + mask(st.oauth_token))
        var next = function () { performOAuth(changes) }
        if (st.master_token) next()
        else exchangeToken(next)
    }
}
