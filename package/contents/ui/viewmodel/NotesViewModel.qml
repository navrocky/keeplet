import QtQuick
import "../../code/nodes.js" as Nodes
import "../../code/keepapi.js" as KeepApi

// ViewModel for the notes list: owns the synced state, exposes what to show and
// the commands to change it. No visual items and no user-facing strings: errors are
// codes that the View translates. Depends only on `auth` (needs signedIn, email,
// token(), invalidateToken()) and optional injected `cache` (load/save/remove).
QtObject {
    id: vm

    // --- Dependencies
    required property var auth
    property var cache: null
    // Replaces the HTTP transport (tests). Signature: (authToken, requestBody) => Promise.
    property var transport: null
    property int syncInterval: 5 // minutes

    // --- Output
    property var notes: []        // visible notes, pinned first
    property var labels: []       // all labels, by name
    property bool syncing: false
    property bool loaded: false   // there is something to show (cache or server)
    property var lastSync: null   // Date or null
    // "network" | "unauthorized" | "failed" | "" ; details for "failed" in errorDetail
    property string error: ""
    property string errorDetail: ""

    // --- Input (filters set by the View)
    property string searchText: ""
    property string labelId: ""
    property string view: "notes" // "notes" | "archive" | "trash"

    // --- Private
    property var _state: Nodes.createState()
    property var _all: []
    property string _cacheKey: ""
    readonly property bool _signedIn: auth.signedIn

    property Timer _timer: Timer {
        interval: Math.max(1, vm.syncInterval) * 60 * 1000
        repeat: true
        running: vm._signedIn
        onTriggered: vm.refresh()
    }

    // --- Commands
    function refresh() {
        if (syncing || !auth.signedIn)
            return
        syncing = true
        error = ""
        errorDetail = ""
        _sync(false).then(function () {
            lastSync = new Date()
            loaded = true
            if (cache && _cacheKey)
                cache.save(_cacheKey, JSON.stringify(_state))
            _rebuild()
        }).catch(function (e) {
            _fail(e)
        }).then(function () {
            syncing = false
        })
    }

    // --- Internals
    function _sync(retried) {
        return auth.token().then(function (token) {
            return KeepApi.sync(token, _state, [], transport || undefined)
        }).catch(function (e) {
            if (e && e.kind === "Unauthorized" && !retried) {
                auth.invalidateToken()
                return _sync(true)
            }
            throw e
        })
    }

    function _fail(e) {
        if (e && (e.kind === "Network" || e.code === "Network"))
            error = "network"
        else if (e && e.kind === "Unauthorized")
            error = "unauthorized"
        else if (e && e.code)
            error = "" // sign-in problem: AuthViewModel reports it
        else {
            error = "failed"
            errorDetail = String(e)
        }
    }

    function _rebuild() {
        _all = Nodes.buildNotes(_state)
        labels = Nodes.buildLabels(_state)
        _applyFilter()
    }

    function _matches(note, query) {
        var hay = [note.title, note.text]
        note.items.forEach(function (i) { hay.push(i.text) })
        note.labels.forEach(function (l) { hay.push(l.name) })
        return hay.join("\n").toLowerCase().indexOf(query) >= 0
    }

    function _applyFilter() {
        var query = searchText.trim().toLowerCase()
        var out = _all.filter(function (n) {
            if (view === "trash") {
                if (!n.trashed)
                    return false
            } else if (n.trashed || n.archived !== (view === "archive")) {
                return false
            }
            if (labelId && !n.labels.some(function (l) { return l.id === labelId }))
                return false
            return !query || _matches(n, query)
        })
        // Keep's own order, pinned first.
        notes = out.filter(function (n) { return n.pinned })
                   .concat(out.filter(function (n) { return !n.pinned }))
    }

    function _restoreFromCache() {
        if (!cache || !_cacheKey)
            return
        var json = cache.load(_cacheKey)
        if (!json)
            return
        try {
            var s = JSON.parse(json)
            if (s && typeof s.nodes === "object" && typeof s.labels === "object") {
                _state = { version: s.version || "", nodes: s.nodes, labels: s.labels }
                loaded = true
                _rebuild()
            }
        } catch (e) {
            console.warn("Keeplet: ignoring corrupt cache:", e)
        }
    }

    function _start() {
        _cacheKey = auth.email
        _restoreFromCache()
        refresh()
    }

    function _reset() {
        if (cache && _cacheKey)
            cache.remove(_cacheKey)
        _cacheKey = ""
        _state = Nodes.createState()
        _all = []
        notes = []
        labels = []
        loaded = false
        lastSync = null
        error = ""
        errorDetail = ""
    }

    on_SignedInChanged: _signedIn ? _start() : _reset()
    onSearchTextChanged: _applyFilter()
    onLabelIdChanged: _applyFilter()
    onViewChanged: _applyFilter()

    Component.onCompleted: {
        if (_signedIn)
            _start()
    }
}
