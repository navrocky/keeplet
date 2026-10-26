import QtQuick
import QtQuick.LocalStorage as Sql

// The SQLite side of LocalDb: the only file that imports QtQuick.LocalStorage, so LocalDb loads even when
// that module is missing (Debian/Ubuntu ship it separately as qml6-module-qtquick-localstorage).
// Synchronous; LocalDb decides when to call it.
QtObject {
    property var _handle: null

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

    function read(ns, key) {
        var value = ""
        _open().readTransaction(function (tx) {
            var rs = tx.executeSql("SELECT value FROM kv WHERE ns = ? AND key = ?", [ns, key])
            if (rs.rows.length > 0)
                value = rs.rows.item(0).value
        })
        return value
    }

    function set(ns, key, value) {
        _open().transaction(function (tx) {
            tx.executeSql("INSERT OR REPLACE INTO kv (ns, key, value) VALUES (?, ?, ?)", [ns, key, value])
        })
    }

    function remove(ns, key) {
        _open().transaction(function (tx) {
            tx.executeSql("DELETE FROM kv WHERE ns = ? AND key = ?", [ns, key])
        })
    }
}
