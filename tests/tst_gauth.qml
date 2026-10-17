import QtQuick
import QtTest
import "../package/contents/code/providers/keep/gauth.js" as GAuth

TestCase {
    name: "GAuth"

    function test_newAndroidId() {
        var id = GAuth.newAndroidId()
        verify(/^[0-9a-f]{16}$/.test(id), id)
        verify(id !== GAuth.newAndroidId())
    }

    function test_exchangeForm() {
        var f = GAuth.exchangeForm("a@b.c", "oauth2_4/x", "0123456789abcdef")
        compare(f.Email, "a@b.c")
        compare(f.Token, "oauth2_4/x")
        compare(f.ACCESS_TOKEN, 1)
        compare(f.service, "ac2dm")
        compare(f.androidId, "0123456789abcdef")
        compare(f.client_sig, GAuth.CLIENT_SIG)
    }

    function test_oauthForm() {
        var f = GAuth.oauthForm("a@b.c", "aas_et/x", "0123456789abcdef")
        compare(f.EncryptedPasswd, "aas_et/x")
        compare(f.app, "com.google.android.keep")
        verify(f.service.indexOf("auth/memento") > 0)
        verify(f.Token === undefined)
    }

    function test_authError() {
        var e = new GAuth.AuthError("BadAuthentication", 403)
        compare(e.code, "BadAuthentication")
        verify(String(e).indexOf("BadAuthentication") >= 0)
        verify(!GAuth.isNetworkError(e))
        verify(GAuth.isNetworkError(new GAuth.AuthError("Network", 0)))
    }

    function test_exchangeAcceptsEmptyEmail() {
        // Browser sign-in does not know the address: the form just carries an empty Email.
        compare(GAuth.exchangeForm("", "oauth2_4/x", "0123456789abcdef").Email, "")
    }
}
