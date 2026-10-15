import QtQuick
import QtQuick.LocalStorage as Sql

// Persists one JSON snapshot of the notes state per account (SQLite via LocalStorage).
// Failures are non-fatal: the cache is an optimization, the server stays the source of truth.
QtObject {
    function _db() {
        var db = Sql.LocalStorage.openDatabaseSync("keeplet", "", "Keeplet notes cache", 16 * 1024 * 1024)
        db.transaction(function (tx) {
            tx.executeSql("CREATE TABLE IF NOT EXISTS cache (key TEXT PRIMARY KEY, value TEXT)")
        })
        return db
    }

    // Returns the stored JSON string or "".
    function load(key) {
        var value = ""
        try {
            _db().readTransaction(function (tx) {
                var rs = tx.executeSql("SELECT value FROM cache WHERE key = ?", [key])
                if (rs.rows.length > 0)
                    value = rs.rows.item(0).value
            })
        } catch (e) {
            console.warn("Keeplet: cache read failed:", e)
        }
        return value
    }

    function save(key, value) {
        try {
            _db().transaction(function (tx) {
                tx.executeSql("INSERT OR REPLACE INTO cache (key, value) VALUES (?, ?)", [key, value])
            })
        } catch (e) {
            console.warn("Keeplet: cache write failed:", e)
        }
    }

    function remove(key) {
        try {
            _db().transaction(function (tx) {
                tx.executeSql("DELETE FROM cache WHERE key = ?", [key])
            })
        } catch (e) {
            console.warn("Keeplet: cache delete failed:", e)
        }
    }
}
