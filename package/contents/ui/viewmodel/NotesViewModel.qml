import QtQuick
import "../../code/core/workspace.js" as Workspace

// ViewModel for the notes list across all accounts shown by this widget.
// Owns per-account provider state, exposes the merged and filtered notes and the commands.
// No visual items and no user-facing strings: errors are codes (View translates them).
//
// Dependencies: `accounts` (needs `sessions`, see AccountsViewModel) and optional `cache`
// ({load(key), save(key, json), remove(key)}).
QtObject {
    id: vm

    required property var accounts
    property var cache: null
    property int syncInterval: 5 // minutes

    // --- Output
    property var notes: []        // visible notes, pinned first (see Workspace.visibleNotes)
    property var labels: []       // labels of all shown accounts, each with accountKey and key
    property bool syncing: false  // any account is syncing
    property bool loaded: false   // there is something to show (cache or server)
    property var lastSync: null   // Date of the latest successful sync, or null
    // Per-account problems: [{accountKey, displayName, kind, detail}], kind is a ProviderError kind.
    property var errors: []
    // Convenience for single-account Views: the first problem, or "".
    readonly property string error: errors.length > 0 ? errors[0].kind : ""
    readonly property string errorDetail: errors.length > 0 ? errors[0].detail : ""

    // --- Input (filters set by the View)
    property string searchText: ""
    property string labelKey: ""      // "<accountKey>|<labelId>" or ""
    property string accountFilter: "" // accountKey or "" for all
    property string view: "notes"     // "notes" | "archive" | "trash"

    // --- Private
    property var _accs: ({})          // accountKey -> {account, provider, session, state, syncing, lastSync, error}
    property var _all: []
    readonly property var _sessions: accounts.sessions

    property Timer _timer: Timer {
        interval: Math.max(1, vm.syncInterval) * 60 * 1000
        repeat: true
        running: vm._sessions.length > 0
        onTriggered: vm.refresh()
    }

    // --- Commands
    function refresh() {
        Object.keys(_accs).forEach(function (key) { _refreshAccount(key) })
    }

    // --- Internals
    function _fail(e) {
        if (e && e.kind)
            return { kind: e.kind, detail: e.detail || "" }
        return { kind: "failed", detail: String(e) }
    }

    function _refreshAccount(key) {
        var a = _accs[key]
        if (!a || a.syncing)
            return
        a.syncing = true
        a.error = null
        _updateStatus()
        a.session.sync(a.state, []).then(function (state) {
            a.state = state
            a.lastSync = new Date()
            a.loaded = true
            if (cache)
                cache.save(key, JSON.stringify(a.state))
        }).catch(function (e) {
            a.error = _fail(e)
        }).then(function () {
            a.syncing = false
            if (_accs[key] === a) { // the account may have been removed meanwhile
                _rebuild()
                _updateStatus()
            }
        })
    }

    function _updateStatus() {
        var keys = Object.keys(_accs)
        syncing = keys.some(function (k) { return _accs[k].syncing })
        loaded = keys.some(function (k) { return _accs[k].loaded })
        var last = null
        var errs = []
        keys.forEach(function (k) {
            var a = _accs[k]
            if (a.lastSync && (!last || a.lastSync > last))
                last = a.lastSync
            if (a.error)
                errs.push({ accountKey: k, displayName: a.account.displayName, kind: a.error.kind, detail: a.error.detail })
        })
        lastSync = last
        errors = errs
    }

    function _rebuild() {
        var parts = Object.keys(_accs).map(function (k) {
            var a = _accs[k]
            return Workspace.annotate(a.account, a.session.notes(a.state), a.session.labels(a.state))
        })
        var merged = Workspace.merge(parts)
        _all = merged.notes
        labels = merged.labels
        _applyFilter()
    }

    function _applyFilter() {
        notes = Workspace.visibleNotes(_all, {
            accountFilter: accountFilter, view: view, labelKey: labelKey,
            query: searchText, accountCount: Object.keys(_accs).length
        })
    }

    // Adopts the session list: new accounts start from their cache and sync, removed ones are dropped.
    function _adoptSessions() {
        var next = {}
        var fresh = []
        _sessions.forEach(function (s) {
            var key = s.account.key
            var existing = _accs[key]
            if (existing && existing.session === s.session) {
                next[key] = existing
                return
            }
            var a = { account: s.account, provider: s.provider, session: s.session,
                      state: s.session.createState(), syncing: false, lastSync: null, loaded: false, error: null }
            if (cache) {
                var json = cache.load(key)
                if (json) {
                    try {
                        var restored = s.session.restoreState(JSON.parse(json))
                        if (restored) {
                            a.state = restored
                            a.loaded = true
                        }
                    } catch (e) {
                        console.warn("Keeplet: ignoring corrupt cache for", key, e)
                    }
                }
            }
            next[key] = a
            fresh.push(key)
        })
        Object.keys(_accs).forEach(function (key) {
            if (!next[key] && cache)
                cache.remove(key)
        })
        _accs = next
        _rebuild()
        _updateStatus()
        fresh.forEach(function (key) { _refreshAccount(key) })
    }

    on_SessionsChanged: _adoptSessions()
    onSearchTextChanged: _applyFilter()
    onLabelKeyChanged: _applyFilter()
    onAccountFilterChanged: _applyFilter()
    onViewChanged: _applyFilter()

    Component.onCompleted: _adoptSessions()
}
