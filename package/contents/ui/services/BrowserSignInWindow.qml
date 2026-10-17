import QtQuick
import QtQuick.Window
import QtWebEngine

// One sign-in window: shows the provider's web sign-in in a private (off-the-record) profile and reports the
// one-time cookie once the page signals "done" with a URL fragment. Created and destroyed by BrowserSignIn.qml;
// the only file that needs QtWebEngine.
//
// The cookie is HttpOnly, so neither document.cookie nor the QML API can read it. The attached DevTools view
// (kept 1x1 and transparent) speaks the DevTools protocol through InspectorFrontendHost, and
// Network.getAllCookies returns HttpOnly cookies too. Verified by a spike (see git history); see
// docs/decisions/0003-browser-signin.md.
Window {
    id: win

    required property string startUrl
    required property string doneMarker   // URL fragment that means "signed in", e.g. "#close"
    required property string cookie       // name of the cookie that carries the token

    // Token read, email seen on the pages (may be empty).
    signal captured(string token, string email)
    signal failed(string detail)
    signal cancelled()

    property string pageEmail: ""
    property bool _done: false
    property int _attempts: 0

    width: 480
    height: 680
    title: view.title
    visible: true

    WebEngineProfile {
        id: profile
        offTheRecord: true
    }

    WebEngineView {
        id: dev
        width: 1
        height: 1
        opacity: 0
        profile: profile
    }

    WebEngineView {
        id: view
        anchors.fill: parent
        profile: profile
        url: win.startUrl
        Component.onCompleted: devToolsView = dev

        onUrlChanged: {
            if (!win._done && url.toString().endsWith(win.doneMarker)) {
                win._done = true
                poll.start()
            }
        }
        onLoadingChanged: function (info) {
            if (info.status !== WebEngineView.LoadSucceededStatus || win._done)
                return
            // The account address is shown on the password and consent pages.
            runJavaScript("(document.body.innerText.match(/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}/) || [''])[0]",
                function (e) { if (e) win.pageEmail = e })
        }
    }

    // Installs the hook once (it swallows our reply, otherwise DevTools logs the cookie values) and asks for
    // the cookies until the token shows up: the DevTools page may still be loading on the first tries.
    readonly property string _script: "(function(){"
        + "if (!window.DevToolsAPI || !window.InspectorFrontendHost) return null;"
        + "if (!window.__hooked) { window.__hooked = true; window.__tok = null;"
        + "var old = DevToolsAPI.dispatchMessage;"
        + "DevToolsAPI.dispatchMessage = function (m) { try { var o = JSON.parse(m);"
        + "if (o.id === 900001) { (o.result && o.result.cookies || []).forEach(function (c) {"
        + "if (c.name === " + JSON.stringify(cookie) + ") window.__tok = c.value }); return } } catch (e) {}"
        + "return old.apply(this, arguments) } }"
        + "if (window.__tok) return window.__tok;"
        + "InspectorFrontendHost.sendMessageToBackend(JSON.stringify({id: 900001, method: 'Network.getAllCookies'}));"
        + "return null })()"

    Timer {
        id: poll
        interval: 500
        repeat: true
        onTriggered: {
            if (++win._attempts > 30) {
                stop()
                win.failed("cookie not found")
                return
            }
            dev.runJavaScript(win._script, function (token) {
                if (token && poll.running) {
                    poll.stop()
                    win.captured(token, win.pageEmail)
                }
            })
        }
    }

    onClosing: {
        if (!_done)
            cancelled()
    }
}
