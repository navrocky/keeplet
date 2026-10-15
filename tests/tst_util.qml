import QtQuick
import QtTest
import "../package/contents/code/util.js" as Util

TestCase {
    name: "Util"

    function test_parseKeyValue() {
        var kv = Util.parseKeyValue("Token=aas_et/abc=\nExpiry=123\n\ngarbage")
        compare(kv.Token, "aas_et/abc=")
        compare(kv.Expiry, "123")
        compare(Object.keys(kv).length, 2)
    }

    function test_formEncode() {
        compare(Util.formEncode({ a: "x y", b: "a/b=c" }), "a=x%20y&b=a%2Fb%3Dc")
    }
}
