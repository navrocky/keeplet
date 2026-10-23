import QtQuick
import "links.js" as Links

// Links of a plain-text field (the note text, a checklist item): underlined, opened by Ctrl+click (a plain click
// when the field is read-only), right click shows `menu`. Everything else falls through to the field, so typing
// and selecting work as usual. Fill the field with it: `LinkLayer { field: parent; anchors.fill: parent }`.
MouseArea {
    id: linkLayer

    required property Item field   // a TextEdit / TextArea
    required property LinkMenu menu
    property color color: "black"

    readonly property var links: Links.find(field.text)
    // One underline per link and line it covers: {x, y, width, height, url} in field coordinates.
    property var segments: []

    function measure() {
        var out = []
        links.forEach(function (l) {
            var seg = null
            for (var i = l.start; i < l.end; i++) {
                var a = field.positionToRectangle(i)
                var b = field.positionToRectangle(i + 1)
                // A character that ends a wrapped line has no measurable right edge; its line keeps the previous one.
                var right = b.y === a.y ? b.x : a.x
                if (seg !== null && seg.y === a.y) {
                    seg.width = Math.max(seg.width, right - seg.x)
                } else {
                    seg = { x: a.x, y: a.y, width: right - a.x, height: a.height, url: l.url }
                    out.push(seg)
                }
            }
        })
        segments = out
    }
    function remeasure() { Qt.callLater(measure) }
    onLinksChanged: remeasure()
    Component.onCompleted: remeasure()
    Connections {
        target: linkLayer.field
        function onWidthChanged() { linkLayer.remeasure() }
        function onContentHeightChanged() { linkLayer.remeasure() }
        function onFontChanged() { linkLayer.remeasure() }
    }

    function linkAt(x, y) {
        for (var i = 0; i < segments.length; i++) {
            var s = segments[i]
            if (x >= s.x && x < s.x + s.width && y >= s.y && y < s.y + s.height)
                return s.url
        }
        return ""
    }
    function opensOnClick(modifiers) {
        return field.readOnly || (modifiers & Qt.ControlModifier)
    }

    FontMetrics { id: metrics; font: linkLayer.field.font }

    Repeater {
        model: linkLayer.segments
        Rectangle {
            required property var modelData
            x: modelData.x
            y: modelData.y + Math.round((modelData.height - metrics.height) / 2) + metrics.ascent + metrics.underlinePosition
            width: modelData.width
            height: Math.max(1, Math.round(metrics.lineWidth))
            color: linkLayer.color
        }
    }

    // Over a link the pointer turns into a hand when a click would open it.
    HoverHandler {
        id: hover
        cursorShape: linkLayer.linkAt(point.position.x, point.position.y) !== "" && linkLayer.opensOnClick(point.modifiers)
                     ? Qt.PointingHandCursor : Qt.IBeamCursor
    }

    property string pressedUrl: ""
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onPressed: mouse => {
        var url = linkAt(mouse.x, mouse.y)
        if (url !== "" && mouse.button === Qt.RightButton) {
            menu.openFor(url, linkLayer, Qt.point(mouse.x, mouse.y))
        } else if (url !== "" && opensOnClick(mouse.modifiers)) {
            pressedUrl = url
        } else {
            mouse.accepted = false
        }
    }
    onClicked: mouse => {
        if (mouse.button === Qt.LeftButton && pressedUrl !== "" && linkAt(mouse.x, mouse.y) === pressedUrl)
            Qt.openUrlExternally(pressedUrl)
        pressedUrl = ""
    }
    onCanceled: pressedUrl = ""
}
