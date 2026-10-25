import QtQuick
import "../../code/core/analytics.js" as GA

// Anonymous usage statistics (opt-in), shared settings for every widget instance: consent, the random
// client id and the day of the last heartbeat live in LocalDb (namespace "analytics"). Events are sanitized
// by code/core/analytics.js, queued and sent in batches; nothing is sent before the user agrees. Consent is
// read again before every batch and once a minute, so a change made by another instance or the settings is honored.
QtObject {
    id: svc

    required property var db
    property string measurementId: GA.MEASUREMENT_ID
    property string apiSecret: GA.API_SECRET
    // post(url, body) -> Promise(status); tests replace it.
    property var post: GA.post
    // Pause before a batch is sent (ms); tests shorten it.
    property int batchDelay: 10000
    property int reloadInterval: 60000

    readonly property bool configured: GA.configured(measurementId, apiSecret)
    property bool ready: false
    property string consent: ""      // "" (not asked) | "yes" | "no"
    readonly property bool enabled: configured && consent === "yes"

    property string _clientId: ""
    property string _sessionId: GA.newSessionId()
    property var _queue: []

    property Timer _timer: Timer {
        interval: svc.batchDelay
        onTriggered: svc.flush()
    }

    property Timer _reloadTimer: Timer {
        interval: svc.reloadInterval
        repeat: true
        running: svc.configured
        onTriggered: svc._load()
    }

    function track(name, params) {
        if (!configured || (ready && consent !== "yes"))
            return
        var e = GA.sanitize(name, params)
        if (!e)
            return console.warn("Keeplet: unknown analytics event", name)
        _queue.push(e)
        if (_queue.length >= GA.MAX_EVENTS)
            flush()
        else if (!_timer.running)
            _timer.start()
    }

    // app_start at most once a day for all instances together.
    function heartbeat(params) {
        if (!enabled)
            return Promise.resolve()
        var today = GA.day(new Date())
        return db.get("analytics", "lastHeartbeat").then(function (last) {
            if (last === today)
                return
            db.set("analytics", "lastHeartbeat", today)
            track("app_start", params)
        })
    }

    function setConsent(agreed) {
        consent = agreed ? "yes" : "no"
        db.set("analytics", "consent", consent)
        if (!agreed) {
            _queue = []
            _timer.stop()
            _clientId = ""
            db.remove("analytics", "clientId")
            db.remove("analytics", "lastHeartbeat")
            return
        }
        if (!_clientId) {
            _clientId = GA.newClientId()
            db.set("analytics", "clientId", _clientId)
        }
        track("analytics_opt_in")
    }

    // Sends what is queued (after checking that consent still holds).
    function flush() {
        _timer.stop()
        if (_queue.length === 0)
            return Promise.resolve()
        return _load().then(function () {
            if (!enabled || !_clientId) {
                _queue = []
                return
            }
            var batch = _queue.splice(0, GA.MAX_EVENTS)
            if (_queue.length > 0)
                _timer.start()
            return post(GA.url(measurementId, apiSecret), GA.payload(_clientId, _sessionId, batch))
        })
    }

    function _load() {
        return Promise.all([db.get("analytics", "consent"), db.get("analytics", "clientId")]).then(function (v) {
            consent = v[0]
            _clientId = v[1]
            ready = true
            if (consent !== "yes")
                _queue = []
        })
    }

    Component.onCompleted: {
        if (configured)
            _load()
        else
            ready = true
    }
}
