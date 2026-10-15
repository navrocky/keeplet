// Stage 0 spike B: can pure QML store a secret in KWallet over D-Bus?
// Run: QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen qml6 spike/wallet.qml
import QtQuick
import org.kde.plasma.workspace.dbus as DBus

Item {
    readonly property string appId: "Keeplet spike"
    readonly property string folder: "Keeplet"

    function log(msg) { console.log("[wallet] " + msg) }

    function call(service, path, iface, member, args) {
        return new Promise(function (resolve, reject) {
            var msg = { service: service, path: path, iface: iface, member: member, arguments: args || [] }
            // Both callbacks receive the DBusPendingReply itself. Do not set
            // msg.signature: the module infers it, explicit values are rejected.
            DBus.SessionBus.asyncCall(msg,
                function (reply) { resolve(reply.value) },
                function (reply) { reject(reply.error.name + ": " + reply.error.message) })
        })
    }
    function kw(member, args) {
        return call("org.kde.kwalletd6", "/modules/kwalletd6", "org.kde.KWallet", member, args)
    }

    Component.onCompleted: {
        var handle
        call("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "GetId")
        .then(function (id) { log("bus sanity check OK, bus id " + id); return kw("isEnabled") })
        .then(function (enabled) {
            log("isEnabled = " + enabled)
            if (!enabled) throw "KWallet is disabled"
            return kw("networkWallet")
        })
        .then(function (wallet) {
            log("network wallet = " + wallet)
            return kw("open", [wallet, new DBus.int64(0), appId])
        })
        .then(function (h) {
            handle = new DBus.int32(h)
            log("open handle = " + h)
            if (h < 0) throw "open failed"
            return kw("writePassword", [handle, folder, "spike", "s3cret-value", appId])
        })
        .then(function (rc) {
            log("writePassword rc = " + rc)
            return kw("readPassword", [handle, folder, "spike", appId])
        })
        .then(function (v) {
            log("readPassword raw: String=" + String(v).substr(0,3) + " .value=" + (v && String(v.value).substr(0,3)) + " keys=" + Object.keys(v))
            if (v && typeof v === "object" && "value" in v) v = v.value
            log("readPassword: typeof=" + typeof v + " match=" + (v === "s3cret-value"))
            if (v !== "s3cret-value") throw "read mismatch"
            return kw("removeEntry", [handle, folder, "spike", appId])
        })
        .then(function (rc) {
            log("removeEntry rc = " + rc)
            log("RESULT: OK")
            Qt.exit(0)
        })
        .catch(function (e) {
            log("RESULT: FAILED: " + e)
            Qt.exit(1)
        })
    }
}
