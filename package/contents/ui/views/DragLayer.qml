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

    // (x, y) is the pointer, (startWidth, startHeight) the size of the card that is picked up.
    function begin(key, text, x, y, startWidth, startHeight, color) {
        if (active)
            cancel()
        noteKey = key
        title = text
        tint = color
        pointer = Qt.point(x, y)
        // Jump to the card's size without animation, then shrink to the chip.
        ghost.animate = false
        ghost.width = startWidth
        ghost.height = startHeight
        ghost.animate = true
        active = true
        visible = true
        ghost.visible = true
        ghost.width = Qt.binding(function () { return layer.chipWidth })
        ghost.height = Qt.binding(function () { return layer.chipHeight })
        watchdog.restart()
    }

    function moveTo(x, y) {
        if (!active)
            return
        pointer = Qt.point(x, y)
        watchdog.restart()
    }

    // Drops the note where the pointer is. DropAreas under the ghost get onDropped.
    function drop() {
        if (!active)
            return
        var action = ghost.Drag.drop()
        _hide()
        ended(action)
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
        visible: false
        // Centered on the pointer; the size changes while the card shrinks into the chip.
        x: layer.pointer.x - width / 2
        y: layer.pointer.y - height / 2
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

        Drag.active: layer.active
        Drag.source: ghost
        Drag.hotSpot: Qt.point(width / 2, height / 2)

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
