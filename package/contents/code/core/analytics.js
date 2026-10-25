.pragma library

// Anonymous usage statistics via the GA4 Measurement Protocol (opt-in, see docs/analytics.md).
// Only the events and parameters listed in EVENTS ever leave the machine: no note content, label names,
// e-mails, account keys, tokens or error details.

// Substituted by scripts/package.sh from GA_MEASUREMENT_ID / GA_API_SECRET; left as is, statistics are off.
var MEASUREMENT_ID = "@GA_MEASUREMENT_ID@"
var API_SECRET = "@GA_API_SECRET@"

var ENDPOINT = "https://www.google-analytics.com/mp/collect"
var MAX_EVENTS = 25      // per request (GA4 limit)
var MAX_VALUE = 100      // characters of a string parameter (GA4 limit)

// Event name -> allowed parameters.
var EVENTS = {
    app_start: ["widget_version", "locale", "providers", "accounts"],
    analytics_opt_in: [],
    sign_in: ["provider", "method"],
    sign_in_error: ["provider", "kind"],
    account_remove: ["provider"],
    sync_error: ["provider", "kind"],
    note_create: ["type"],
    note_trash: [],
    note_restore: [],
    note_delete: [],
    trash_empty: [],
    note_archive: ["archived"],
    note_pin: ["pinned"],
    note_color: ["color"],
    note_move: [],
    note_drop_label: [],
    note_convert: ["to"],
    checklist_clear_done: [],
    editor_undo: [],
    editor_redo: [],
    label_create: ["provider"],
    label_rename: ["provider"],
    label_delete: ["provider"],
    group_open: ["kind"],
    search: [],
    link_preview: []
}

function configured(measurementId, apiSecret) {
    return !!measurementId && !!apiSecret && measurementId.charAt(0) !== "@" && apiSecret.charAt(0) !== "@"
}

// Returns {name, params, time} with only the allowed parameters, or null for an unknown event.
function sanitize(name, params, now) {
    var allowed = EVENTS[name]
    if (!allowed)
        return null
    var out = {}
    params = params || {}
    allowed.forEach(function (k) {
        var v = params[k]
        if (typeof v === "string")
            out[k] = v.substr(0, MAX_VALUE)
        else if (typeof v === "number" && isFinite(v))
            out[k] = v
        else if (typeof v === "boolean")
            out[k] = v ? "true" : "false"
    })
    return { name: name, params: out, time: now !== undefined ? now : Date.now() }
}

// Request body for up to MAX_EVENTS sanitized events.
function payload(clientId, sessionId, events) {
    return {
        client_id: clientId,
        events: events.slice(0, MAX_EVENTS).map(function (e) {
            var params = { session_id: sessionId, engagement_time_msec: 1 }
            for (var k in e.params)
                params[k] = e.params[k]
            return { name: e.name, params: params, timestamp_micros: e.time * 1000 }
        })
    }
}

function url(measurementId, apiSecret) {
    return ENDPOINT + "?measurement_id=" + encodeURIComponent(measurementId)
            + "&api_secret=" + encodeURIComponent(apiSecret)
}

// Resolves with the HTTP status (0 when unreachable); never rejects.
function post(target, body) {
    return new Promise(function (resolve) {
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function () {
            if (xhr.readyState === XMLHttpRequest.DONE)
                resolve(xhr.status)
        }
        xhr.open("POST", target)
        xhr.setRequestHeader("Content-Type", "application/json")
        xhr.send(JSON.stringify(body))
    })
}

// Random UUID v4 (not tied to any account).
function newClientId() {
    return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, function (c) {
        var r = Math.random() * 16 | 0
        return (c === "x" ? r : (r & 3 | 8)).toString(16)
    })
}

function newSessionId() {
    return String(Math.floor(Date.now() / 1000))
}

// "YYYY-MM-DD" in local time.
function day(date) {
    function pad(n) { return (n < 10 ? "0" : "") + n }
    return date.getFullYear() + "-" + pad(date.getMonth() + 1) + "-" + pad(date.getDate())
}
