.pragma library

// New versions of the widget: the product's Version field on the KDE Store, read through its OCS API
// (the same catalog Plasma's Get New Widgets and Discover install from, see docs/release.md).

var PRODUCT_ID = "2379427"
var PROVIDER_ID = "api.kde-look.org"     // the KDE Store in KNewStuff (plasmoids.knsrc)
var ENDPOINT = "https://api.kde-look.org/ocs/v1/content/data/" + PRODUCT_ID + "?format=json"
var STORE_URL = "https://store.kde.org/p/" + PRODUCT_ID + "/"
var CHECK_INTERVAL = 24 * 3600 * 1000    // ms between checks, shared by every widget instance

// [x, y, z] of a release version, null for anything else (dev builds, "1.2", "1.2.3-4-gabc1234").
function parse(version) {
    var m = /^(\d+)\.(\d+)\.(\d+)$/.exec(String(version || "").trim())
    return m ? [Number(m[1]), Number(m[2]), Number(m[3])] : null
}

// < 0, 0 or > 0 as a is older than, equal to or newer than b (both parse()d).
function compare(a, b) {
    for (var i = 0; i < 3; i++) {
        if (a[i] !== b[i])
            return a[i] - b[i]
    }
    return 0
}

// A local build that is not a release (0.0.0-dev…, commits after a tag) never offers an update.
function isNewer(latest, current) {
    var l = parse(latest), c = parse(current)
    return !!l && !!c && compare(l, c) > 0
}

// The product version from an OCS content/data answer (parsed JSON), "" if there is none.
function parseLatest(answer) {
    if (!answer || String(answer.status) !== "ok" || !answer.data || !answer.data.length)
        return ""
    var v = String(answer.data[0].version || "").trim()
    return parse(v) ? v : ""
}

// Resolves with the latest version, "" when the store is unreachable or answers nonsense; never rejects.
function fetchLatest() {
    return new Promise(function (resolve) {
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return
            var answer = null
            try { answer = JSON.parse(xhr.responseText) } catch (e) {}
            resolve(xhr.status === 200 ? parseLatest(answer) : "")
        }
        xhr.open("GET", ENDPOINT)
        xhr.send()
    })
}
