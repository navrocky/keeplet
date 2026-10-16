import QtQuick

// Persists one JSON snapshot of provider state per account key. The cache is an optimization:
// the server stays the source of truth, so failures are ignored by LocalDb. All calls are asynchronous.
QtObject {
    required property var db

    // Resolves with the stored JSON string or "".
    function load(key) { return db.get("cache", key) }
    function save(key, json) { return db.set("cache", key, json) }
    function remove(key) { return db.remove("cache", key) }
    // Writes everything that is still queued, now (the widget is going away).
    function flush() { db.drain() }
}
