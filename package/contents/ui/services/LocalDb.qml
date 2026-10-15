import QtQuick
import QtQuick.LocalStorage as Sql

// Small key-value store shared by every widget instance (SQLite via LocalStorage).
// Values are strings; namespaces keep registry, secrets and cache apart.
// Failures are non-fatal and logged: reads return "" / [].
QtObject {
    function _db() {
        var db = Sql.LocalStorage.openDatabaseSync("keeplet", "", "Keeplet", 16 * 1024 * 1024)
        db.transaction(function (tx) {
            tx.executeSql("CREATE TABLE IF NOT EXISTS kv (ns TEXT, key TEXT, value TEXT, PRIMARY KEY (ns, key))")
        })
        return db
    }

    function get(ns, key) {
        var value = ""
        try {
            _db().readTransaction(function (tx) {
                var rs = tx.executeSql("SELECT value FROM kv WHERE ns = ? AND key = ?", [ns, key])
                if (rs.rows.length > 0)
                    value = rs.rows.item(0).value
            })
        } catch (e) {
            console.warn("Keeplet: db read failed:", e)
        }
        return value
    }

    function set(ns, key, value) {
        try {
            _db().transaction(function (tx) {
                tx.executeSql("INSERT OR REPLACE INTO kv (ns, key, value) VALUES (?, ?, ?)", [ns, key, value])
            })
        } catch (e) {
            console.warn("Keeplet: db write failed:", e)
        }
    }

    function remove(ns, key) {
        try {
            _db().transaction(function (tx) {
                tx.executeSql("DELETE FROM kv WHERE ns = ? AND key = ?", [ns, key])
            })
        } catch (e) {
            console.warn("Keeplet: db delete failed:", e)
        }
    }
}
