import QtQuick
import "../../code/core/errors.js" as Errors
import "../../code/providers/registry.js" as DefaultRegistry

// ViewModel for accounts: which accounts this widget shows, their provider sessions,
// and sign-in/remove commands. No visuals and no user-facing text: errors are codes.
//
// Dependencies (injected so tests can fake them):
//   service  - {list(), save(account), remove(key), readSecret(key), writeSecret(key, v)}
//   registry - {list(), get(id)} of providers (default: the release registry)
//   configuration - per-instance config; only `accountKeys` (list, empty = all accounts) is read
QtObject {
    id: vm

    required property var service
    property var registry: DefaultRegistry
    property var configuration: ({ accountKeys: [] })
    // Test hook: (account) => options passed to provider.createSession().
    property var sessionOptions: null

    // [{key, providerId, accountId, providerName, icon, displayName, capabilities, needsSignIn}]
    property var accounts: []
    // [{account, provider: {id, name, icon, capabilities}, session}] for accounts whose secret is available.
    property var sessions: []
    readonly property bool signedIn: accounts.length > 0
    readonly property bool multiAccount: accounts.length > 1
    // Providers a new account can be added for (drives the sign-in form).
    readonly property var providers: registry.list().map(function (p) {
        return { id: p.id, name: p.name, icon: p.icon, credentialFields: p.credentialFields,
                 signInHelpUrl: p.signInHelpUrl || "" }
    })

    // False until the first load of the stored accounts has finished (avoids flashing the sign-in form).
    property bool ready: false
    property bool busy: false
    property bool signInRequested: false   // show the sign-in form even though accounts exist
    // {providerId, accountId} of the account the form signs in again, or null for a new account.
    property var signInTarget: null
    // "" | "network" | "badCredentials" | "exists" | "failed" ; details for "failed" in errorDetail
    property string error: ""
    property string errorDetail: ""

    readonly property var _scope: configuration.accountKeys || []

    function reload() {
        var scope = _scope
        var generation = ++_generation
        return service.list().then(function (all) {
            return all.filter(function (a) {
                return scope.length === 0 || scope.indexOf(a.key) >= 0
            })
        }).then(function (stored) {
            return Promise.all(stored.map(function (account) {
            var provider = registry.get(account.providerId)
            if (!provider)
                return Promise.resolve({ account: account, provider: null, secret: "" })
            return service.readSecret(account.key).then(function (secret) {
                return { account: account, provider: provider, secret: secret }
            }, function () {
                return { account: account, provider: provider, secret: "" }
            })
        })).then(function (items) {
            if (generation !== _generation)
                return // a newer reload superseded this one
            var accs = []
            var sess = []
            items.forEach(function (it) {
                var p = it.provider
                var ready = !!(p && it.secret)
                accs.push({
                    key: it.account.key,
                    providerId: it.account.providerId,
                    accountId: it.account.accountId,
                    providerName: p ? p.name : it.account.providerId,
                    icon: p ? p.icon : "dialog-question",
                    displayName: it.account.displayName,
                    capabilities: p ? p.capabilities : null,
                    needsSignIn: !ready
                })
                if (ready) {
                    var opts = sessionOptions ? sessionOptions(it.account) : undefined
                    // Plain data only: a provider module object loses its members once stored in a
                    // `property var`, so sessions carry a copy of what the ViewModels need.
                    sess.push({
                        account: it.account,
                        provider: { id: p.id, name: p.name, icon: p.icon, capabilities: p.capabilities },
                        session: p.createSession(it.account, it.secret, opts)
                    })
                }
            })
            accounts = accs
            sessions = sess
            ready = true
        })
        })
    }

    // Signing in again replaces the secret of a service account, but a persistent account (local notes) has
    // nothing to sign in to: the same name would silently join two notebooks. Rejects with kind "exists".
    function duplicate(provider, key) {
        if (!provider.capabilities.persistent || signInTarget)
            return Promise.resolve()
        return service.list().then(function (all) {
            if (all.some(function (a) { return a.key === key }))
                throw { kind: "exists" }
        })
    }

    function signIn(providerId, creds) {
        var provider = registry.get(providerId)
        if (!provider || busy)
            return
        busy = true
        error = ""
        errorDetail = ""
        provider.signIn(creds).then(function (r) {
            var key = providerId + ":" + r.accountId
            return duplicate(provider, key).then(function () {
                return service.writeSecret(key, r.secret)
            }).then(function () {
                return service.save({ key: key, providerId: providerId, accountId: r.accountId,
                                      displayName: r.displayName, meta: r.meta || {} })
            }).then(function () {
                signInRequested = false
                signInTarget = null
                return reload()
            })
        }).catch(function (e) {
            if (Errors.isProviderError(e) || (e && e.kind)) {
                error = e.kind
                errorDetail = e.detail || ""
            } else {
                error = "failed"
                errorDetail = String(e)
            }
        }).then(function () {
            busy = false
        })
    }

    // Forgets an account everywhere (registry, secret, cache).
    function remove(accountKey) {
        return service.remove(accountKey).then(function () { return reload() })
    }

    // `target` ({providerId, accountId}) signs an existing account in again; without it a new account is added.
    function requestSignIn(target) { error = ""; errorDetail = ""; signInTarget = target || null; signInRequested = true }
    function cancelSignIn() { error = ""; errorDetail = ""; signInTarget = null; signInRequested = false }

    property int _generation: 0

    // Picks up changes of the widget's account selection made in its settings.
    // (Only a real config object, i.e. a QObject, can be watched; tests pass a plain object.)
    property Connections _configWatcher: Connections {
        target: vm.configuration && vm.configuration.objectName !== undefined ? vm.configuration : null
        ignoreUnknownSignals: true
        function onAccountKeysChanged() { vm.reload() }
        // The settings dialog (another QML context) added or removed an account.
        function onAccountsRevisionChanged() { vm.reload() }
    }

    // Not on configurationChanged: properties are assigned in arbitrary order during creation,
    // so `service` may still be unset at that point.
    Component.onCompleted: reload()
}
