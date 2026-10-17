import QtQuick

// Opens a provider's web sign-in in its own window and resolves with the token the page leaves in a cookie.
// Only a thin loader: the window (BrowserSignInWindow.qml) is the sole user of QtWebEngine, so when that
// module is missing `available` is false and the manual token form stays the only way in.
QtObject {
    id: service

    // Created lazily; "Ready" only if the QtWebEngine import resolves.
    property var _component: null
    property bool available: false

    // request: {startUrl, doneMarker, cookie}. Resolves with {token, email}; rejects with {kind}:
    // "cancelled" (window closed), "failed" (detail) or "unavailable".
    function signIn(request) {
        return new Promise(function (resolve, reject) {
            if (!available)
                return reject({ kind: "unavailable" })
            var win = _component.createObject(null, {
                startUrl: request.startUrl, doneMarker: request.doneMarker, cookie: request.cookie
            })
            if (!win)
                return reject({ kind: "failed", detail: "window" })
            var finish = function (fn, arg) {
                win.visible = false
                win.destroy(1000)
                fn(arg)
            }
            win.captured.connect(function (token, email) { finish(resolve, { token: token, email: email }) })
            win.failed.connect(function (detail) { finish(reject, { kind: "failed", detail: detail }) })
            win.cancelled.connect(function () { finish(reject, { kind: "cancelled" }) })
        })
    }

    Component.onCompleted: {
        var c = Qt.createComponent("BrowserSignInWindow.qml")
        if (c.status === Component.Ready) {
            _component = c
            available = true
        } else {
            console.info("Keeplet: browser sign-in unavailable:", c.errorString().split("\n")[0])
        }
    }
}
