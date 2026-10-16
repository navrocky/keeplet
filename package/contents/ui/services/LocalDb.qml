import QtQuick
import QtQuick.LocalStorage as Sql

// Small key-value store shared by every widget instance (SQLite via LocalStorage).
// Values are strings; namespaces keep registry, secrets and cache apart.
//
// The API is asynchronous (promises). QtQuick.LocalStorage is synchronous and unavailable in a WorkerScript
// (measured: the module cannot be imported there), so the SQLite calls still run on the UI thread, but never
// inside the caller: operations are queued and executed one per event-loop turn, so rendering and input get
// their turns between them, writes to one key are coalesced (only the newest value is written), and a read
// of a key with a pending write is answered from memory. Failures are non-fatal: reads resolve "", writes
// resolve after a warning. drain() runs everything left synchronously (used when the widget goes away).
QtObject {
    id: db

    // Queue of {ns, key, op: "get"|"set"|"remove", value, resolvers: [fn(result)]}, oldest first.
    property var _queue: []
    // "<ns>\u0000<key>" -> the pending write task of that key (also in _queue).
    property var _pendingWrite: ({})
    property var _handle: null

    property Timer _pump: Timer {
        interval: 0
        repeat: false
        onTriggered: db._step()
    }

    function get(ns, key) {
        var pending = _pendingWrite[_id(ns, key)]
        if (pending)
            return Promise.resolve(pending.op === "set" ? pending.value : "")
        return _enqueue({ ns: ns, key: key, op: "get" })
    }

    function set(ns, key, value) {
        return _write({ ns: ns, key: key, op: "set", value: value })
    }

    function remove(ns, key) {
        return _write({ ns: ns, key: key, op: "remove" })
    }

    // Number of operations still waiting.
    property int pending: 0

    // Executes everything that is queued, now. Returns nothing; promises resolve as usual.
    function drain() {
        _pump.stop()
        while (_queue.length > 0)
            _run(_queue.shift())
        pending = 0
    }

    function _id(ns, key) { return ns + "\u0000" + key }

    function _write(task) {
        var id = _id(task.ns, task.key)
        var existing = _pendingWrite[id]
        return new Promise(function (resolve) {
            if (existing) {
                // Newer write for the same key: the older one is not needed any more.
                existing.op = task.op
                existing.value = task.value
                existing.resolvers.push(resolve)
                return
            }
            task.resolvers = [resolve]
            _pendingWrite[id] = task
            _push(task)
        })
    }

    function _enqueue(task) {
        return new Promise(function (resolve) {
            task.resolvers = [resolve]
            _push(task)
        })
    }

    function _push(task) {
        _queue.push(task)
        pending = _queue.length
        _pump.restart()
    }

    function _step() {
        if (_queue.length === 0)
            return
        _run(_queue.shift())
        pending = _queue.length
        if (_queue.length > 0)
            _pump.restart()
    }

    function _run(task) {
        var id = _id(task.ns, task.key)
        if (_pendingWrite[id] === task)
            delete _pendingWrite[id]
        var result = ""
        try {
            if (task.op === "get")
                result = _read(task.ns, task.key)
            else if (task.op === "set")
                _set(task.ns, task.key, task.value)
            else
                _remove(task.ns, task.key)
        } catch (e) {
            console.warn("Keeplet: db", task.op, "failed:", e)
        }
        task.resolvers.forEach(function (resolve) { resolve(result) })
    }

    function _open() {
        if (_handle)
            return _handle
        var h = Sql.LocalStorage.openDatabaseSync("keeplet", "", "Keeplet", 16 * 1024 * 1024)
        h.transaction(function (tx) {
            tx.executeSql("CREATE TABLE IF NOT EXISTS kv (ns TEXT, key TEXT, value TEXT, PRIMARY KEY (ns, key))")
        })
        _handle = h
        return h
    }

    function _read(ns, key) {
        var value = ""
        _open().readTransaction(function (tx) {
            var rs = tx.executeSql("SELECT value FROM kv WHERE ns = ? AND key = ?", [ns, key])
            if (rs.rows.length > 0)
                value = rs.rows.item(0).value
        })
        return value
    }

    function _set(ns, key, value) {
        _open().transaction(function (tx) {
            tx.executeSql("INSERT OR REPLACE INTO kv (ns, key, value) VALUES (?, ?, ?)", [ns, key, value])
        })
    }

    function _remove(ns, key) {
        _open().transaction(function (tx) {
            tx.executeSql("DELETE FROM kv WHERE ns = ? AND key = ?", [ns, key])
        })
    }

    Component.onDestruction: drain()
}
