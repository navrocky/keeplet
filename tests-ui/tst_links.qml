import QtQuick
import QtQuick.Controls as QQC2
import QtTest
import "../package/contents/ui/views" as V

// Links in the views: a card finds the link under a point, the editor's layer underlines and finds them.
Item {
    width: 400; height: 400

    V.NoteCard {
        id: card
        width: 300
        note: ({ type: "NOTE", title: "", pinned: false, color: "DEFAULT", labels: [], items: [],
                 text: "https://example.com is here" })
    }

    QQC2.TextArea {
        id: area
        y: 200
        width: 300
        wrapMode: TextEdit.Wrap
        text: "go to www.kde.org now"
        V.LinkLayer { id: layer; anchors.fill: parent; field: parent; menu: menu }
    }
    V.LinkMenu { id: menu }

    TestCase {
        name: "LinkViews"
        when: windowShown

        function test_cardFindsTheLinkUnderAPoint() {
            var body = card.children[0].children[1]
            var p = card.mapFromItem(body, 5, body.height / 2)
            compare(card.linkAt(p.x, p.y), "https://example.com")
            var q = card.mapFromItem(body, body.width - 2, body.height / 2)
            compare(card.linkAt(q.x, q.y), "")
        }

        function test_layerUnderlinesAndFindsLinks() {
            tryVerify(function () { return layer.segments.length === 1 })
            var s = layer.segments[0]
            verify(s.width > 0)
            compare(layer.linkAt(s.x + 1, s.y + 1), "https://www.kde.org")
            compare(layer.linkAt(s.x - 2, s.y + 1), "")
            area.text = "no links"
            tryVerify(function () { return layer.segments.length === 0 })
        }

        function test_plainClickOnALinkEditsTheText() {
            area.text = "go to www.kde.org now"
            tryVerify(function () { return layer.segments.length === 1 })
            var s = layer.segments[0]
            area.cursorPosition = 0
            mouseClick(area, s.x + s.width / 2, s.y + s.height / 2)
            verify(area.activeFocus)
            verify(area.cursorPosition > 6 && area.cursorPosition < 17, "cursor at " + area.cursorPosition)
        }

        function test_phoneAndEmailAreLinksToo() {
            area.text = "call +7 (999) 123-45-67 or a@b.cc"
            tryVerify(function () { return layer.segments.length === 2 })
            compare(layer.segments[0].url, "tel:+79991234567")
            compare(layer.segments[1].url, "mailto:a@b.cc")
        }

        function test_wrappedLinkGetsOneUnderlinePerLine() {
            area.text = "x https://example.com/" + "a".repeat(120)
            tryVerify(function () { return layer.segments.length > 1 })
        }
    }
}
