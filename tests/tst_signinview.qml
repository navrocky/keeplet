import QtQuick
import QtTest
import "../package/contents/ui/views"
import "../package/contents/ui/viewmodel"

TestCase {
    name: "SignInView"; when: windowShown
    width: 600; height: 500
    QtObject { id: svc
        function list() { return Promise.resolve([]) }
        function save() { return Promise.resolve() }
        function remove() { return Promise.resolve() }
        function readSecret() { return Promise.resolve("") }
        function writeSecret() { return Promise.resolve() } }
    AccountsViewModel { id: vm; service: svc }
    SignInView { id: v; accounts: vm; width: 500; height: 400 }
    function findAll(item, pred, out) {
        out = out || []
        if (pred(item)) out.push(item)
        for (var i = 0; i < item.children.length; i++) findAll(item.children[i], pred, out)
        return out
    }
    function test_typingANameEnablesAddForLocal() {
        wait(200)
        v.children[1].currentIndex = 1   // combo
        wait(100)
        compare(v.provider.id, "local")
        var fields = findAll(v, function (o) { return o.placeholderText === "Account name" })
        compare(fields.length, 1)
        fields[0].forceActiveFocus()
        keyClick("H"); keyClick("i")
        wait(100)
        compare(v.values.name, "Hi")
        var btns = findAll(v, function (o) { return o.hasOwnProperty("icon") && o.hasOwnProperty("down") && o.text === "Add" })
        compare(btns.length, 1)
        verify(btns[0].enabled)   // typing a name enables "Add"
    }
}
