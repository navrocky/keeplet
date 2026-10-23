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
        V.LinkLayer { id: layer; anchors.fill: parent; field: parent; menu: menu; preview: preview }
    }
    V.LinkMenu { id: menu }
    V.LinkPreview { id: preview }

    TestCase {
        name: "LinkViews"
        when: windowShown

        // The first underline of a link, once the layer has measured the current text.
        function segmentOf(url) {
            var found = null
            tryVerify(function () {
                found = layer.segments.filter(function (s) { return s.url === url })[0] || null
                return found !== null
            })
            return found
        }

        function test_cardFindsTheLinkUnderAPoint() {
            var body = card.children[0].children[1]
            var p = card.mapFromItem(body, 5, body.height / 2)
            compare(card.linkAt(p.x, p.y), "https://example.com")
            var q = card.mapFromItem(body, body.width - 2, body.height / 2)
            compare(card.linkAt(q.x, q.y), "")
        }

        function test_layerUnderlinesAndFindsLinks() {
            area.text = "go to www.kde.org now"
            var s = segmentOf("https://www.kde.org")
            compare(layer.segments.length, 1)
            verify(s.width > 0)
            compare(layer.linkAt(s.x + 1, s.y + 1), "https://www.kde.org")
            compare(layer.linkAt(s.x - 2, s.y + 1), "")
            area.text = "no links"
            tryVerify(function () { return layer.segments.length === 0 })
        }

        function test_plainClickOnALinkEditsTheText() {
            area.text = "go to www.kde.org now"
            var s = segmentOf("https://www.kde.org")
            area.cursorPosition = 0
            mouseClick(area, s.x + s.width / 2, s.y + s.height / 2)
            verify(area.activeFocus)
            verify(area.cursorPosition > 6 && area.cursorPosition < 17, "cursor at " + area.cursorPosition)
        }

        function test_phoneAndEmailAreLinksToo() {
            area.text = "call +7 (999) 123-45-67 or a@b.cc"
            segmentOf("tel:+79991234567")
            segmentOf("mailto:a@b.cc")
        }

        function test_restingOnAWebLinkShowsItsPreview() {
            if (!preview.available)
                skip("QtWebEngine is not available")
            area.text = "go to http://127.0.0.1:9/page now, call +7 999 123 45 67"
            var web = segmentOf("http://127.0.0.1:9/page"), phone = segmentOf("tel:+79991234567")
            mouseMove(area, web.x + 3, web.y + web.height / 2)
            tryVerify(function () { return preview.opened }, 3000)
            compare(preview.url, "http://127.0.0.1:9/page")
            // Next to the link, never over it, and inside the window.
            var top = area.mapToItem(preview.parent, 0, web.y).y
            var bottom = top + web.height
            verify(preview.y >= bottom || preview.y + preview.height <= top,
                   "popup " + preview.y + "+" + preview.height + " vs link " + top + ".." + bottom)
            verify(preview.y >= 0 && preview.y + preview.height <= preview.parent.height)
            verify(preview.x >= 0 && preview.x + preview.width <= preview.parent.width)
            // Leaving the link (not into the popup) closes it; a phone number has no preview.
            mouseMove(area, phone.x + 3, phone.y + phone.height / 2)
            tryVerify(function () { return !preview.opened }, 3000)
            wait(1000)
            verify(!preview.opened)
        }

        function test_clickInTheFieldHidesThePreview() {
            if (!preview.available)
                skip("QtWebEngine is not available")
            area.text = "go to http://127.0.0.1:9/page now"
            var web = segmentOf("http://127.0.0.1:9/page")
            mouseMove(area, web.x + 3, web.y + web.height / 2)
            tryVerify(function () { return preview.opened }, 3000)
            mouseClick(area, web.x + 3, web.y + web.height / 2)
            tryVerify(function () { return !preview.opened })
        }

        function test_wrappedLinkGetsOneUnderlinePerLine() {
            area.text = "x https://example.com/" + "a".repeat(120)
            tryVerify(function () { return layer.segments.length > 1 })
        }
    }
}
