import QtQuick
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

// The floating "ghost" of a note that is being dragged.
//
// It is a sibling of the screen's layout, never a child of it, and it is invisible (so it takes no part in
// layout or pointer handling) unless a drag runs. A drag always ends: by drop(), by cancel(), when the owner
// reports that the dragged card is gone, or after the watchdog timeout without any pointer update.
Item {
    id: layer

    property bool active: false
    property string noteKey: ""
    property string title: ""
    property color tint: Kirigami.Theme.backgroundColor
    // Pointer position in this item's coordinates while a drag is active.
    property point pointer: Qt.point(0, 0)

    // The ghost starts as the card and shrinks to this chip under the pointer.
    readonly property real chipWidth: Math.min(width - Kirigami.Units.largeSpacing * 2, Kirigami.Units.gridUnit * 10)
    readonly property real chipHeight: label.implicitHeight + Kirigami.Units.largeSpacing * 2

    // Emitted after drop(): the action returned by the drop targets (Qt.IgnoreAction if nobody took it).
    signal ended(int action)
    signal cancelled()

    // A drag without pointer updates for this long is abandoned (the release was lost somewhere).
    property int watchdogInterval: 8000

    visible: false

    // The chip hangs below and to the right of the pointer, so the target under it stays visible.
    readonly property real chipGrabX: Kirigami.Units.gridUnit
    readonly property real chipGrabY: Kirigami.Units.gridUnit * 0.6

    // The pointer is at (x, y); the picked-up card occupies (cardX, cardY, cardWidth, cardHeight), all in this
    // item's coordinates. The ghost starts exactly over the card and shrinks into the chip next to the pointer.
    function begin(key, text, x, y, cardX, cardY, cardWidth, cardHeight, color) {
        if (active)
            cancel()
        noteKey = key
        title = text
        tint = color
        pointer = Qt.point(x, y)
        ghost.animate = false
        ghost.width = cardWidth
        ghost.height = cardHeight
        ghost.grabX = x - cardX
        ghost.grabY = y - cardY
        ghost.animate = true
        active = true
        visible = true
        ghost.visible = true
        ghost.width = Qt.binding(function () { return layer.chipWidth })
        ghost.height = Qt.binding(function () { return layer.chipHeight })
        ghost.grabX = Qt.binding(function () { return layer.chipGrabX })
        ghost.grabY = Qt.binding(function () { return layer.chipGrabY })
        watchdog.restart()
    }

    function moveTo(x, y) {
        if (!active)
            return
        pointer = Qt.point(x, y)
        watchdog.restart()
    }

    // Drops the note where the pointer is. DropAreas under the ghost get onDropped. Returns the action a
    // target accepted, Qt.IgnoreAction if none did (and when no drag was running).
    function drop() {
        if (!active)
            return Qt.IgnoreAction
        var action = ghost.Drag.drop()
        _hide()
        ended(action)
        return action
    }

    function cancel() {
        if (!active)
            return
        ghost.Drag.cancel()
        _hide()
        cancelled()
    }

    function _hide() {
        watchdog.stop()
        active = false
        ghost.visible = false
        visible = false
        noteKey = ""
    }

    Timer {
        id: watchdog
        interval: layer.watchdogInterval
        onTriggered: layer.cancel()
    }

    Rectangle {
        id: ghost
        property bool animate: true
        // Where the pointer is inside the ghost; moves from the grab point on the card to the chip's corner.
        property real grabX: 0
        property real grabY: 0
        visible: false
        x: layer.pointer.x - grabX
        y: layer.pointer.y - grabY
        width: layer.chipWidth
        height: layer.chipHeight
        radius: Kirigami.Units.smallSpacing * 2
        color: layer.tint
        border.color: Kirigami.Theme.highlightColor
        border.width: 2
        opacity: 0.92

        Behavior on width {
            enabled: ghost.animate
            NumberAnimation { duration: Kirigami.Units.longDuration; easing.type: Easing.OutCubic }
        }
        Behavior on height {
            enabled: ghost.animate
            NumberAnimation { duration: Kirigami.Units.longDuration; easing.type: Easing.OutCubic }
        }
        Behavior on grabX {
            enabled: ghost.animate
            NumberAnimation { duration: Kirigami.Units.longDuration; easing.type: Easing.OutCubic }
        }
        Behavior on grabY {
            enabled: ghost.animate
            NumberAnimation { duration: Kirigami.Units.longDuration; easing.type: Easing.OutCubic }
        }

        Drag.active: layer.active
        Drag.source: ghost
        // The drop position is the pointer itself, wherever the chip hangs.
        Drag.hotSpot: Qt.point(grabX, grabY)

        // The drop targets read the dragged note from the drag source.
        property string noteKey: layer.noteKey

        PlasmaComponents.Label {
            id: label
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            text: layer.title
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
        }
    }
}
