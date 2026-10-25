import QtQuick
import QtTest
import "../package/contents/ui/viewmodel" as VM
import "../package/contents/code/providers/fake.js" as Fake
import "../package/contents/code/providers/local/index.js" as Local

TestCase {
    id: tc
    name: "AccountsViewModel"
    when: windowShown

    // In-memory stand-in for services/AccountsService.qml.
    Component {
        id: serviceComp
        QtObject {
            property var accounts: []
            property var secrets: ({})
            property var removed: []
            function list() { return Promise.resolve(JSON.parse(JSON.stringify(accounts))) }
            function save(a) {
                accounts = accounts.filter(function (x) { return x.key !== a.key }).concat([a])
                return Promise.resolve()
            }
            function remove(key) {
                accounts = accounts.filter(function (x) { return x.key !== key })
                delete secrets[key]
                removed.push(key)
                return Promise.resolve()
            }
            function readSecret(key) { return Promise.resolve(secrets[key] || "") }
            function writeSecret(key, v) { secrets[key] = v; return Promise.resolve() }
        }
    }
    Component { id: vmComp; VM.AccountsViewModel {} }

    readonly property var registry: ({
        list: function () { return [Fake] },
        get: function (id) { return id === "fake" ? Fake : null }
    })

    function acc(name) {
        return { key: "fake:" + name, providerId: "fake", accountId: name, displayName: name, meta: {} }
    }

    function make(stored, secrets, config) {
        var svc = serviceComp.createObject(tc, { accounts: stored || [], secrets: secrets || {} })
        var vm = vmComp.createObject(tc, { service: svc, registry: registry, configuration: config || { accountKeys: [] } })
        return { vm: vm, svc: svc }
    }

    function test_startsEmpty() {
        var c = make()
        wait(20)
        verify(!c.vm.signedIn)
        verify(!c.vm.multiAccount)
        compare(c.vm.sessions.length, 0)
    }

    function test_loadsStoredAccountsWithSessions() {
        var c = make([acc("a"), acc("b")], { "fake:a": "s1", "fake:b": "s2" })
        tryVerify(function () { return c.vm.sessions.length === 2 })
        verify(c.vm.signedIn)
        verify(c.vm.multiAccount)
        compare(c.vm.accounts[0].providerName, "Fake")
        compare(c.vm.accounts[0].needsSignIn, false)
    }

    function test_accountWithoutSecretNeedsSignInAndHasNoSession() {
        var c = make([acc("a"), acc("b")], { "fake:a": "s1" })
        tryVerify(function () { return c.vm.accounts.length === 2 })
        compare(c.vm.sessions.length, 1)
        var b = c.vm.accounts.filter(function (x) { return x.key === "fake:b" })[0]
        verify(b.needsSignIn)
    }

    function test_unknownProviderIsKeptButNotUsable() {
        var stored = [{ key: "gone:x", providerId: "gone", accountId: "x", displayName: "x", meta: {} }]
        var c = make(stored, { "gone:x": "s" })
        tryVerify(function () { return c.vm.accounts.length === 1 })
        compare(c.vm.sessions.length, 0)
        verify(c.vm.accounts[0].needsSignIn)
    }

    function test_instanceScopeLimitsAccounts() {
        var c = make([acc("a"), acc("b")], { "fake:a": "s1", "fake:b": "s2" }, { accountKeys: ["fake:b"] })
        tryVerify(function () { return c.vm.accounts.length === 1 })
        compare(c.vm.accounts[0].key, "fake:b")
        verify(!c.vm.multiAccount)
    }

    function test_signInStoresSecretAndAccount() {
        var c = make()
        c.vm.signIn("fake", { name: "new" })
        tryVerify(function () { return c.vm.sessions.length === 1 })
        compare(c.svc.secrets["fake:new"], "fake-secret")
        compare(c.svc.accounts[0].accountId, "new")
        verify(!c.vm.busy)
        compare(c.vm.error, "")
    }

    function test_signInFailureReportsCodeAndStoresNothing() {
        var c = make()
        c.vm.signIn("fake", { name: "bad" })
        tryVerify(function () { return c.vm.error === "badCredentials" })
        compare(c.svc.accounts.length, 0)
        verify(!c.vm.busy)
    }

    function test_signInIsReportedToAnalytics() {
        var events = []
        var c = make()
        c.vm.analytics = { track: function (name, params) { events.push(name + ":" + JSON.stringify(params)) } }
        c.vm.signIn("fake", { name: "bad" })
        tryVerify(function () { return !c.vm.busy && c.vm.error !== "" })
        c.vm.signIn("fake", { name: "new" })
        tryVerify(function () { return c.vm.sessions.length === 1 })
        compare(events.join(" "), 'sign_in_error:{"provider":"fake","kind":"badCredentials"} '
                + 'sign_in:{"provider":"fake","method":"password"}')
    }

    function test_signInHidesFormAfterSuccess() {
        var c = make([acc("a")], { "fake:a": "s" })
        tryVerify(function () { return c.vm.signedIn })
        c.vm.requestSignIn()
        verify(c.vm.signInRequested)
        c.vm.signIn("fake", { name: "b" })
        tryVerify(function () { return c.vm.accounts.length === 2 })
        verify(!c.vm.signInRequested)
    }

    function test_cancelSignIn() {
        var c = make([acc("a")], { "fake:a": "s" })
        tryVerify(function () { return c.vm.signedIn })
        c.vm.requestSignIn()
        c.vm.cancelSignIn()
        verify(!c.vm.signInRequested)
    }

    function test_removeForgetsAccount() {
        var c = make([acc("a"), acc("b")], { "fake:a": "s1", "fake:b": "s2" })
        tryVerify(function () { return c.vm.sessions.length === 2 })
        c.vm.remove("fake:a")
        tryVerify(function () { return c.vm.sessions.length === 1 })
        compare(c.svc.removed.join(), "fake:a")
        compare(c.vm.accounts[0].key, "fake:b")
    }

    function test_providersExposeCredentialFields() {
        var c = make()
        compare(c.vm.providers.length, 1)
        compare(c.vm.providers[0].credentialFields[0].key, "name")
    }

    // --- several providers, several accounts of one provider

    readonly property var mixedRegistry: ({
        list: function () { return [Fake, Local] },
        get: function (id) { return id === "fake" ? Fake : (id === "local" ? Local : null) }
    })

    function makeMixed() {
        var svc = serviceComp.createObject(tc, {})
        var vm = vmComp.createObject(tc, { service: svc, registry: mixedRegistry })
        return { vm: vm, svc: svc }
    }

    function test_severalAccountsOfOneProviderAndAccountIdExposed() {
        var c = make([acc("a"), acc("b")], { "fake:a": "s1", "fake:b": "s2" })
        tryVerify(function () { return c.vm.accounts.length === 2 })
        compare(c.vm.accounts[0].accountId, "a")
        compare(c.vm.accounts[1].providerName, "Fake")
        verify(c.vm.multiAccount)
    }

    function test_signInToDifferentProviders() {
        var c = makeMixed()
        tryVerify(function () { return c.vm.ready })
        compare(c.vm.providers.length, 2)
        c.vm.signIn("fake", { name: "x" })
        tryVerify(function () { return c.vm.accounts.length === 1 })
        c.vm.signIn("local", { name: "Home" })
        tryVerify(function () { return c.vm.accounts.length === 2 })
        compare(c.vm.accounts[1].key, "local:Home")
        compare(c.vm.accounts[1].providerName, "Local notes")
    }

    function test_sameNameTwiceIsRejectedForLocalButNotForServiceAccounts() {
        var c = makeMixed()
        tryVerify(function () { return c.vm.ready })
        c.vm.signIn("local", { name: "Home" })
        tryVerify(function () { return c.vm.accounts.length === 1 })
        c.vm.signIn("local", { name: "Home" })
        tryVerify(function () { return c.vm.error === "exists" })
        compare(c.svc.accounts.length, 1)
        c.vm.signIn("fake", { name: "x" })
        tryVerify(function () { return c.vm.accounts.length === 2 })
        c.vm.signIn("fake", { name: "x" })   // signing in again to a service account is fine
        tryVerify(function () { return !c.vm.busy && c.vm.error === "" })
        compare(c.svc.accounts.length, 2)
    }

    function test_requestSignInCanTargetAnAccount() {
        var c = make([acc("a")], { "fake:a": "s1" })
        c.vm.requestSignIn({ providerId: "fake", accountId: "a" })
        compare(c.vm.signInTarget.accountId, "a")
        verify(c.vm.signInRequested)
        c.vm.cancelSignIn()
        compare(c.vm.signInTarget, null)
    }

    // A provider with a browser sign-in and a fake window service.
    readonly property var browserProvider: ({
        id: "web", name: "Web", icon: "x", capabilities: Fake.capabilities, credentialFields: Fake.credentialFields,
        browserSignIn: { startUrl: "https://example.org", doneMarker: "#close", cookie: "tok", credentialKey: "token" },
        signIn: function (creds) {
            return Promise.resolve({ accountId: creds.email || "from-server", displayName: "web", secret: creds.token, meta: {} })
        },
        createSession: Fake.createSession
    })
    readonly property var webRegistry: ({
        list: function () { return [browserProvider] },
        get: function (id) { return id === "web" ? browserProvider : null }
    })

    function makeWeb(browser) {
        var svc = serviceComp.createObject(tc, {})
        var vm = vmComp.createObject(tc, { service: svc, registry: webRegistry, browser: browser,
                                           configuration: { accountKeys: [] } })
        return { vm: vm, svc: svc }
    }

    function test_browserSignInStoresTokenAndLearnedAccount() {
        var requests = []
        var c = makeWeb({ available: true, signIn: function (r) {
            requests.push(r)
            return Promise.resolve({ token: "T", email: "" })
        } })
        verify(c.vm.browserAvailable)
        c.vm.signInWithBrowser("web")
        tryCompare(c.vm, "busy", false)
        compare(requests[0].cookie, "tok")
        compare(c.svc.secrets["web:from-server"], "T")
        compare(c.vm.error, "")
    }

    function test_browserCancelIsNotAnError() {
        var c = makeWeb({ available: true, signIn: function () { return Promise.reject({ kind: "cancelled" }) } })
        c.vm.signInWithBrowser("web")
        tryCompare(c.vm, "busy", false)
        compare(c.vm.error, "")
        compare(c.svc.accounts.length, 0)
    }

    function test_browserFailureReportsCode() {
        var c = makeWeb({ available: true, signIn: function () { return Promise.reject({ kind: "failed", detail: "cookie not found" }) } })
        c.vm.signInWithBrowser("web")
        tryCompare(c.vm, "error", "failed")
        compare(c.vm.errorDetail, "cookie not found")
    }

    function test_browserUnavailableDoesNothing() {
        var called = false
        var c = makeWeb({ available: false, signIn: function () { called = true; return Promise.resolve({}) } })
        verify(!c.vm.browserAvailable)
        c.vm.signInWithBrowser("web")
        verify(!called)
        verify(!c.vm.busy)
    }

    function test_browserSignInAgainRejectsOtherAccount() {
        var c = makeWeb({ available: true, signIn: function () { return Promise.resolve({ token: "T", email: "other" }) } })
        c.vm.requestSignIn({ providerId: "web", accountId: "mine" })
        c.vm.signInWithBrowser("web")
        tryCompare(c.vm, "error", "wrongAccount")
        compare(c.svc.accounts.length, 0)
    }
}
