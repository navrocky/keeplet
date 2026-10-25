import QtQuick
import QtTest
import "../package/contents/code/core/updates.js" as Updates

TestCase {
    name: "Updates"

    function test_parse() {
        compare(JSON.stringify(Updates.parse("1.10.2")), "[1,10,2]")
        compare(JSON.stringify(Updates.parse(" 0.9.0 ")), "[0,9,0]")
        compare(Updates.parse("1.2"), null)
        compare(Updates.parse("v1.2.3"), null)
        compare(Updates.parse("0.9.0-3-gabc1234"), null)
        compare(Updates.parse("0.0.0-dev.12+abc1234"), null)
        compare(Updates.parse(""), null)
        compare(Updates.parse(undefined), null)
    }

    function test_isNewer() {
        verify(Updates.isNewer("0.10.0", "0.9.0"))
        verify(Updates.isNewer("1.0.0", "0.99.99"))
        verify(Updates.isNewer("0.9.1", "0.9.0"))
        verify(!Updates.isNewer("0.9.0", "0.9.0"))
        verify(!Updates.isNewer("0.8.5", "0.9.0"))
        verify(!Updates.isNewer("", "0.9.0"))
    }

    function test_devBuildsAreNeverOffered() {
        verify(!Updates.isNewer("1.0.0", "0.0.0-dev.3+abc1234"))
        verify(!Updates.isNewer("1.0.0", "0.9.0-3-gabc1234"))
    }

    function test_parseLatest() {
        compare(Updates.parseLatest({ status: "ok", data: [{ id: "2379427", version: "0.9.0" }] }), "0.9.0")
        compare(Updates.parseLatest({ status: "ok", data: [{ version: "0.0.1 beta" }] }), "")
        compare(Updates.parseLatest({ status: "ok", data: [] }), "")
        compare(Updates.parseLatest({ status: "failed", statuscode: 999, message: "unknown request" }), "")
        compare(Updates.parseLatest(null), "")
    }
}
