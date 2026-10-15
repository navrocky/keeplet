import QtQuick

// Persists one JSON snapshot of provider state per account key. The cache is an optimization:
// the server stays the source of truth, so failures are ignored by LocalDb.
QtObject {
    required property var db

    // Returns the stored JSON string or "".
    function load(key) { return db.get("cache", key) }
    function save(key, json) { db.set("cache", key, json) }
    function remove(key) { db.remove("cache", key) }
}
