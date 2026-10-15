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

    function list() {
        var json = db.get(registryNs, registryKey)
        if (!json)
            return []
        try {
            var parsed = JSON.parse(json)
            return Array.isArray(parsed) ? parsed : []
        } catch (e) {
            console.warn("Keeplet: ignoring corrupt account registry:", e)
            return []
        }
    }

    function _store(accounts) {
        db.set(registryNs, registryKey, JSON.stringify(accounts))
    }

    // Adds or replaces an account (matched by key).
    function save(account) {
        var accounts = list().filter(function (a) { return a.key !== account.key })
        accounts.push(account)
        _store(accounts)
    }

    // Forgets the account: registry entry, secret and cached notes.
    function remove(key) {
        _store(list().filter(function (a) { return a.key !== key }))
        db.remove("cache", key)
        return secrets.remove(key)
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
        var known = list().some(function (a) { return a.key === plan.account.key })
        if (known) {
            clear()
            return Promise.resolve(false)
        }
        var getSecret = plan.inlineSecret ? Promise.resolve(plan.inlineSecret) : secrets.read(plan.legacySecretKey)
        return getSecret.then(function (secret) {
            if (!secret) {
                clear() // nothing to carry over: the user signs in again
                return false
            }
            return secrets.write(plan.account.key, secret).then(function () {
                save(plan.account)
                clear()
                return true
            })
        })
    }
}
