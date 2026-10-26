import QtQuick
import QtWebEngine
import "previewProfile.js" as PreviewProfile

// Signs out of every site in the previews' profile: drops its cookies (session cookies are HttpOnly and QML has no
// cookie API, so this goes through the DevTools protocol of a hidden view, like services/BrowserSignInWindow.qml)
// and its HTTP cache. Created for one run by main.qml; emits finished(ok) and can then be destroyed.
Item {
    id: signOut

    signal finished(bool ok)

    width: 1
    height: 1
    opacity: 0

    property int _attempts: 0

    WebEngineView {
        id: dev
        anchors.fill: parent
        profile: PreviewProfile.get()
    }

    WebEngineView {
        id: page
        anchors.fill: parent
        profile: PreviewProfile.get()
        url: "about:blank"
        Component.onCompleted: devToolsView = dev
    }

    // Sends Network.clearBrowserCookies once and reports when the reply came (the hook swallows the reply).
    readonly property string _script: "(function(){"
        + "if (!window.DevToolsAPI || !window.InspectorFrontendHost) return false;"
        + "if (!window.__hooked) { window.__hooked = true; window.__cleared = false;"
        + "var old = DevToolsAPI.dispatchMessage;"
        + "DevToolsAPI.dispatchMessage = function (m) { try { if (JSON.parse(m).id === 900002) { window.__cleared = true; return } }"
        + " catch (e) {} return old.apply(this, arguments) };"
        + "InspectorFrontendHost.sendMessageToBackend(JSON.stringify({id: 900002, method: 'Network.clearBrowserCookies'})) }"
        + "return window.__cleared })()"

    Timer {
        interval: 300
        repeat: true
        running: true
        onTriggered: {
            if (++signOut._attempts > 50) {
                stop()
                signOut.finished(false)
                return
            }
            dev.runJavaScript(signOut._script, function (cleared) {
                if (cleared && running) {
                    stop()
                    PreviewProfile.get().clearHttpCache()
                    signOut.finished(true)
                }
            })
        }
    }
}
