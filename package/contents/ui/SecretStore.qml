import QtQuick
import org.kde.plasma.workspace.dbus as DBus

// Stores one secret per key in KWallet (over D-Bus) when it is enabled,
// otherwise in the widget config (configuration.secretFallback).
// See docs/auth.md for the D-Bus module quirks handled here.
QtObject {
    id: store

    required property var configuration

    // "kwallet" or "config"; empty until the first operation detects it.
    property string backend: ""

    readonly property string appId: "Keeplet"
    readonly property string folder: "Keeplet"

    function _kwallet(member, args) {
        return new Promise(function (resolve, reject) {
            DBus.SessionBus.asyncCall({
                service: "org.kde.kwalletd6",
                path: "/modules/kwalletd6",
                iface: "org.kde.KWallet",
                member: member,
                arguments: args || []
            }, function (reply) {
                var v = reply.value
                // Some replies arrive wrapped as {value: ...}.
                if (v !== null && typeof v === "object" && "value" in v)
                    v = v.value
                resolve(v)
            }, function (reply) {
                reject(new Error(reply.error.name + ": " + reply.error.message))
            })
        })
    }

    function _detect() {
        if (backend)
            return Promise.resolve(backend)
        // A disabled KWallet makes kwalletd6 exit on activation, so errors mean "no KWallet".
        return _kwallet("isEnabled").then(function (enabled) {
            return enabled ? "kwallet" : "config"
        }, function () {
            return "config"
        }).then(function (b) {
            backend = b
            return b
        })
    }

    // open() blocks while KWallet asks for the wallet password and the D-Bus call
    // times out after ~25 s; retrying picks up the wallet once the user unlocks it.
    function _open(wallet, attempt) {
        attempt = attempt || 0
        return _kwallet("open", [wallet, new DBus.int64(0), appId]).then(function (h) {
            if (h < 0)
                throw new Error("KWallet: access denied")
            return h
        }, function (e) {
            if (attempt < 4 && String(e).indexOf("NoReply") >= 0)
                return _open(wallet, attempt + 1)
            throw e
        })
    }

    function _withWallet(fn) {
        return _kwallet("networkWallet").then(function (wallet) {
            return _open(wallet)
        }).then(function (h) {
            var handle = new DBus.int32(h)
            var close = function () { _kwallet("close", [handle, false, appId]) }
            return fn(handle).then(function (v) { close(); return v },
                                   function (e) { close(); throw e })
        })
    }

    function read(key) {
        return _detect().then(function (b) {
            if (b !== "kwallet")
                return configuration.secretFallback
            return _withWallet(function (h) {
                return _kwallet("readPassword", [h, folder, key, appId])
            }).then(function (v) {
                // Secret saved while KWallet was disabled still counts.
                return v || configuration.secretFallback
            })
        })
    }

    function write(key, value) {
        return _detect().then(function (b) {
            if (b !== "kwallet") {
                configuration.secretFallback = value
                return
            }
            return _withWallet(function (h) {
                return _kwallet("writePassword", [h, folder, key, value, appId])
            }).then(function (rc) {
                if (rc !== 0)
                    throw new Error("KWallet: write failed (" + rc + ")")
                configuration.secretFallback = ""
            })
        })
    }

    function remove(key) {
        configuration.secretFallback = ""
        return _detect().then(function (b) {
            if (b !== "kwallet")
                return
            return _withWallet(function (h) {
                return _kwallet("removeEntry", [h, folder, key, appId])
            })
        })
    }
}
