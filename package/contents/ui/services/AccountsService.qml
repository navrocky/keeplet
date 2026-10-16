import QtQuick
import "../../code/core/migration.js" as Migration

// Global (per-user) account registry and secrets, shared by all widget instances.
// Account: {key: "<providerId>:<accountId>", providerId, accountId, displayName, meta}.
QtObject {
    id: service

    required property var db
    property SecretStore secrets: SecretStore { db: service.db }

    readonly property string registryNs: "accounts"
    readonly property string registryKey: "list"

    // Resolves with the accounts ([] when the registry is empty or unreadable).
    function list() {
        return db.get(registryNs, registryKey).then(function (json) {
            if (!json)
                return []
            try {
                var parsed = JSON.parse(json)
                return Array.isArray(parsed) ? parsed : []
            } catch (e) {
                console.warn("Keeplet: ignoring corrupt account registry:", e)
                return []
            }
        })
    }

    function _store(accounts) {
        return db.set(registryNs, registryKey, JSON.stringify(accounts))
    }

    // Adds or replaces an account (matched by key).
    function save(account) {
        return list().then(function (accounts) {
            accounts = accounts.filter(function (a) { return a.key !== account.key })
            accounts.push(account)
            return _store(accounts)
        })
    }

    // Forgets the account: registry entry, secret and cached notes.
    function remove(key) {
        return list().then(function (accounts) {
            return _store(accounts.filter(function (a) { return a.key !== key }))
        }).then(function () {
            return db.remove("cache", key)
        }).then(function () {
            return secrets.remove(key)
        })
    }

    function readSecret(key) { return secrets.read(key) }
    function writeSecret(key, value) { return secrets.write(key, value) }

    // Moves the old per-instance single-account config into the registry.
    // Resolves with true when an account was migrated.
    function migrateLegacy(configuration) {
        var plan = Migration.planLegacy(configuration)
        if (!plan)
            return Promise.resolve(false)
        function clear() {
            configuration.email = ""
            configuration.androidId = ""
            configuration.secretFallback = ""
        }
        return list().then(function (accounts) {
            if (accounts.some(function (a) { return a.key === plan.account.key })) {
                clear()
                return false
            }
            var getSecret = plan.inlineSecret ? Promise.resolve(plan.inlineSecret) : secrets.read(plan.legacySecretKey)
            return getSecret.then(function (secret) {
                if (!secret) {
                    clear() // nothing to carry over: the user signs in again
                    return false
                }
                return secrets.write(plan.account.key, secret).then(function () {
                    return save(plan.account)
                }).then(function () {
                    clear()
                    return true
                })
            })
        })
    }
}
