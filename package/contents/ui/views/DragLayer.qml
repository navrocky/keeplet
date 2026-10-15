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
    // Pointer position in this item's coordinates while a drag is active.
    property point pointer: Qt.point(0, 0)

    // Emitted after drop(): the action returned by the drop targets (Qt.IgnoreAction if nobody took it).
    signal ended(int action)
    signal cancelled()

    // A drag without pointer updates for this long is abandoned (the release was lost somewhere).
    property int watchdogInterval: 8000

    visible: false

    function begin(key, text, x, y) {
        if (active)
            cancel()
        noteKey = key
        title = text
        pointer = Qt.point(x, y)
        ghost.x = x - ghost.width / 2
        ghost.y = y - ghost.height / 2
        active = true
        visible = true
        ghost.visible = true
        watchdog.restart()
    }

    function moveTo(x, y) {
        if (!active)
            return
        pointer = Qt.point(x, y)
        ghost.x = x - ghost.width / 2
        ghost.y = y - ghost.height / 2
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
        visible: false
        width: Math.min(layer.width - Kirigami.Units.largeSpacing * 2, Kirigami.Units.gridUnit * 12)
        height: label.implicitHeight + Kirigami.Units.largeSpacing * 2
        radius: Kirigami.Units.smallSpacing * 2
        color: Kirigami.Theme.backgroundColor
        border.color: Kirigami.Theme.highlightColor
        border.width: 2
        opacity: 0.9

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
