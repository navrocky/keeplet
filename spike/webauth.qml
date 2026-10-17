// Spike: can a WebEngineView capture the oauth_token after Google EmbeddedSetup sign-in?
// Run: qml6 spike/webauth.qml   (sign in; watch the console). Values are masked: only lengths/names are printed.
import QtQuick
import QtQuick.Window
import QtWebEngine

Window {
    id: win
    width: 520; height: 720; visible: true
    title: "webauth spike"

    function mask(s) { return s ? s.substring(0, 4) + "…(" + s.length + ")" : "" }

    WebEngineProfile {
        id: profile
        offTheRecord: true
    }

    // (d) HttpOnly cookies via the embedded DevTools frontend: it talks CDP through InspectorFrontendHost.
    // Hidden: 1x1 and transparent, but still a live view so the frontend loads.
    WebEngineView {
        id: dev
        width: 1; height: 1; opacity: 0
        profile: profile
    }

    function readCookies() {
        var hook = "window.__ck = null; (function(){ var old = DevToolsAPI.dispatchMessage;"
            + "DevToolsAPI.dispatchMessage = function(m){ try { var o = JSON.parse(m);"
            + "if (o.id === 900001) { window.__ck = JSON.stringify((o.result && o.result.cookies || []).map(function(c){"
            + "return {n:c.name, d:c.domain, h:c.httpOnly, len:c.value.length, p:c.value.substring(0,4)} })); return; } } catch(e){}"
            + "return old.apply(this, arguments) };"
            + "InspectorFrontendHost.sendMessageToBackend(JSON.stringify({id:900001, method:'Network.getAllCookies'})) })()"
        dev.runJavaScript(hook, function () {
            poll.start()
        })
    }
    Timer {
        id: poll
        interval: 700
        onTriggered: dev.runJavaScript("window.__ck", function (r) { console.log("(d) cookies:", r) })
    }

    WebEngineView {
        id: view
        anchors.fill: parent
        profile: profile
        Component.onCompleted: devToolsView = dev
        url: "https://accounts.google.com/EmbeddedSetup"

        onUrlChanged: {
            var u = url.toString()
            var qi = u.indexOf("?"), hi = u.indexOf("#")
            var names = qi < 0 ? "" : u.substring(qi + 1, hi < 0 ? u.length : hi).split("&").map(function (p) { return p.split("=")[0] }).join(",")
            if (hi >= 0 && u.substring(hi) === "#close") { console.log("== #close reached"); win.readCookies() }
            console.log("url:", qi < 0 ? u : u.substring(0, qi), "params:", names, "fragment:", hi < 0 ? "" : u.substring(hi, hi + 20) + "…")
        }
        onTitleChanged: console.log("title:", title)
        onNewWindowRequested: function (req) {
            console.log("newwindow:", mask(req.requestedUrl.toString()), req.requestedUrl.toString().split("?")[0], "dest:", req.destination, "user:", req.userInitiated)
            view.url = req.requestedUrl
        }
        onJavaScriptConsoleMessage: function (level, msg, line, src) {
            console.log("js-console:", level, msg.substring(0, 200), src.split("?")[0])
        }
        onRenderProcessTerminated: function (st, code) { console.log("render terminated:", st, code) }
        onNavigationRequested: function (req) {
            console.log("nav:", req.url.toString().replace(/\?.*/, "?…"), "main:", req.isMainFrame)
        }
        onLoadingChanged: function (info) {
            console.log("load status:", info.status, "http:", info.httpStatusCode, "err:", info.errorString)
            if (info.status !== WebEngineView.LoadSucceededStatus)
                return
            console.log("loaded:", url.toString().replace(/\?.*/, "?…"))
            // (a) document.cookie: lists visible cookie names only (HttpOnly are hidden)
            runJavaScript("document.cookie.split('; ').map(function(c){return c.split('=')[0]}).join(',')",
                function (names) { console.log("(a) visible cookie names:", names) })
            // (b) look for token-like strings in the DOM / location
            runJavaScript("(function(){var h=document.documentElement.outerHTML;"
                + "var m=h.match(/(oauth_token|oauth_code|aas_et|oauth2_4)[^\"'<\\s]{0,12}/g);"
                + "return JSON.stringify({loc:location.hash.length+':'+location.search.length,hits:m})})()",
                function (r) { console.log("(b) dom hits:", r) })
        }
    }
}
