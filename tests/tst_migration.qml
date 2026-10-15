import QtQuick
import QtTest
import "../package/contents/code/core/migration.js" as Migration

TestCase {
    name: "Migration"

    function test_nothingToMigrateWithoutEmail() {
        verify(Migration.planLegacy(null) === null)
        verify(Migration.planLegacy({}) === null)
        verify(Migration.planLegacy({ email: "  " }) === null)
    }

    function test_plansKeepAccount() {
        var plan = Migration.planLegacy({ email: " me@example.com ", androidId: "abc", secretFallback: "tok" })
        compare(plan.account.key, "keep:me@example.com")
        compare(plan.account.providerId, "keep")
        compare(plan.account.accountId, "me@example.com")
        compare(plan.account.meta.androidId, "abc")
        compare(plan.legacySecretKey, "me@example.com")
        compare(plan.inlineSecret, "tok")
    }

    function test_missingInlineSecretIsEmpty() {
        compare(Migration.planLegacy({ email: "a@b.c" }).inlineSecret, "")
    }
}
