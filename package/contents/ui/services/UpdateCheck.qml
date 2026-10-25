import QtQuick
import "../../code/core/updates.js" as Updates

// Looks up the latest version on the KDE Store at most once a day for every widget instance together:
// the time of the last successful check, the version found and the one the user dismissed live in
// LocalDb (namespace "updates"). Read again on every poll, so what another instance found shows here too.
QtObject {
    id: svc

    required property var db
    property bool enabled: true
    // fetch() -> Promise(version | ""), now() -> ms; tests replace them.
    property var fetch: Updates.fetchLatest
    property var now: function () { return Date.now() }
    property int pollInterval: 3 * 3600 * 1000

    property bool ready: false
    property string latest: ""
    property string dismissed: ""

    property Timer _timer: Timer {
        interval: svc.pollInterval
        repeat: true
        running: svc.enabled
        onTriggered: svc.check()
    }

    // Loads the shared state and asks the store if the last check is a day old (or failed).
    function check() {
        return _load().then(function (lastCheck) {
            if (!enabled || now() - lastCheck < Updates.CHECK_INTERVAL)
                return
            return fetch().then(function (version) {
                if (!version)
                    return
                latest = version
                db.set("updates", "latest", version)
                db.set("updates", "lastCheck", String(now()))
            })
        })
    }

    // Hides the notice until a newer version than this one comes out.
    function dismiss(version) {
        dismissed = version
        db.set("updates", "dismissed", version)
    }

    function _load() {
        return Promise.all([db.get("updates", "latest"), db.get("updates", "dismissed"),
                            db.get("updates", "lastCheck")]).then(function (v) {
            latest = v[0]
            dismissed = v[1]
            ready = true
            return Number(v[2]) || 0
        })
    }

    onEnabledChanged: if (enabled) check()
    Component.onCompleted: if (enabled) check()
}
