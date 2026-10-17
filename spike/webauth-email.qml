// Spike: after the browser sign-in, which Email does exchange_token accept? Values are masked.
// Run: qml6 spike/webauth-email.qml   (sign in, press "I agree", wait). One-time token: one run = one attempt series.
import QtQuick
import QtQuick.Window
import QtWebEngine
import "../package/contents/code/providers/keep/gauth.js" as Gauth

Window {
    id: win
    width: 520; height: 720; visible: true
    title: "webauth email spike"

    property string pageEmail: ""   // e-mail seen on a sign-in page
    property string userId: ""
    property string oauthToken: ""

    function mask(s) { return s ? s.substring(0, 3) + "…(" + s.length + ")" : "<empty>" }
    function maskEmail(s) { var i = s.indexOf("@"); return i < 0 ? mask(s) : s.substring(0, 2) + "…" + s.substring(i) }

    WebEngineProfile { id: profile; offTheRecord: true }

    WebEngineView { id: dev; width: 1; height: 1; opacity: 0; profile: profile }

    function readCookies() {
        var hook = "window.__tok = null; window.__uid = null; (function(){ var old = DevToolsAPI.dispatchMessage;"
            + "DevToolsAPI.dispatchMessage = function(m){ try { var o = JSON.parse(m);"
            + "if (o.id === 900001) { (o.result.cookies || []).forEach(function(c){"
            + "if (c.name === 'oauth_token') window.__tok = c.value; if (c.name === 'user_id') window.__uid = c.value }); return; } } catch(e){}"
            + "return old.apply(this, arguments) };"
            + "InspectorFrontendHost.sendMessageToBackend(JSON.stringify({id:900001, method:'Network.getAllCookies'})) })()"
        dev.runJavaScript(hook, function () { poll.start() })
    }
    Timer {
        id: poll
        interval: 800
        onTriggered: dev.runJavaScript("JSON.stringify([window.__tok, window.__uid])", function (r) {
            var a = JSON.parse(r)
            win.oauthToken = a[0] || ""
            win.userId = a[1] || ""
            console.log("token:", mask(win.oauthToken), "user_id:", mask(win.userId), "page email:", maskEmail(win.pageEmail))
            if (win.oauthToken) win.tryExchange()
        })
    }

    // Candidates, in an order where a rejection does not (hopefully) burn the token.
    property var candidates: []
    function tryExchange() {
        candidates = [["empty", ""], ["user_id", userId], ["page email", pageEmail]].filter(function (c) {
            return c[0] === "empty" || c[1] !== ""
        })
        next()
    }
    function next() {
        if (candidates.length === 0) { console.log("== all candidates rejected"); return }
        var c = candidates.shift()
        Gauth.exchangeToken(c[1], oauthToken, Gauth.newAndroidId()).then(function (master) {
            console.log("== ACCEPTED with Email =", c[0], "master:", mask(master))
        }, function (e) {
            console.log("rejected with Email =", c[0], "->", e.code, e.status)
            next()
        })
    }

    WebEngineView {
        id: view
        anchors.fill: parent
        profile: profile
        url: "https://accounts.google.com/EmbeddedSetup"
        Component.onCompleted: devToolsView = dev

        onUrlChanged: {
            var u = url.toString()
            if (u.indexOf("#close") >= 0) { console.log("== #close reached"); win.readCookies() }
        }
        onLoadingChanged: function (info) {
            if (info.status !== WebEngineView.LoadSucceededStatus)
                return
            // The account e-mail is shown on the password / consent pages.
            runJavaScript("(document.body.innerText.match(/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}/) || [''])[0]",
                function (e) { if (e) win.pageEmail = e })
        }
    }
}
