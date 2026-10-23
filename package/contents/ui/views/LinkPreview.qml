import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

// A preview of a web link: the page itself, scaled down, in a popup under (or above) the link. hover() is called
// while the pointer is on a link, unhover() when it leaves; the popup opens after the pointer rests a moment and
// closes a moment after the pointer left both the link and the popup. One per widget, shared by the screens.
// The web view is optional (LinkPreviewPage.qml is the only user of QtWebEngine): without it `available` is false.
QQC2.Popup {
    id: popup

    property bool active: true                    // the user's setting
    property var pageComponent: null
    readonly property bool available: pageComponent !== null
    property string url: ""                       // the page shown

    property string pending: ""
    property Item pendingItem: null
    property rect pendingRect

    // `rect`: the link (or the pointer) in `item` coordinates; the popup avoids covering it.
    function hover(link, item, rect) {
        if (!active || !available)
            return
        hideTimer.stop()
        if (opened && link === url)
            return
        pending = link
        pendingItem = item
        pendingRect = rect
        showTimer.restart()
    }
    function unhover() {
        showTimer.stop()
        pending = ""
        if (opened)
            hideTimer.restart()
    }
    function dismiss() {
        showTimer.stop()
        hideTimer.stop()
        pending = ""
        close()
    }

    function showPending() {
        var host = parent
        if (!host || !pendingItem || pending === "")
            return
        var m = Kirigami.Units.smallSpacing
        var r = pendingItem.mapToItem(host, pendingRect.x, pendingRect.y, pendingRect.width, pendingRect.height)
        // Under the link, or above it when there is more room there; never over it.
        var below = r.y + r.height + m
        var roomBelow = host.height - m - below
        var roomAbove = r.y - 2 * m
        var w = Math.min(Kirigami.Units.gridUnit * 24, host.width - 2 * m)
        var h = Math.min(Kirigami.Units.gridUnit * 17, Math.max(roomBelow, roomAbove))
        if (w < Kirigami.Units.gridUnit * 12 || h < Kirigami.Units.gridUnit * 8)
            return
        width = w
        height = h
        x = Math.max(m, Math.min(r.x, host.width - w - m))
        y = h <= roomBelow ? below : r.y - m - h
        url = pending
        loaded = true
        open()
    }

    Timer { id: showTimer; interval: 700; onTriggered: popup.showPending() }
    Timer { id: hideTimer; interval: 400; onTriggered: if (!inside.hovered) popup.close() }

    parent: QQC2.Overlay.overlay
    modal: false
    focus: false
    padding: Kirigami.Units.smallSpacing
    closePolicy: QQC2.Popup.CloseOnEscape | QQC2.Popup.CloseOnPressOutside
    // The page is unloaded when hidden: nothing keeps playing or loading in the background.
    onClosed: url = ""

    // The web view is created on the first preview and then kept.
    property bool loaded: false

    Component.onCompleted: {
        var c = Qt.createComponent("LinkPreviewPage.qml")
        if (c.status === Component.Ready)
            pageComponent = c
        else
            console.log("Keeplet: link previews are off, QtWebEngine is not available")
    }

    function openInBrowser() {
        Qt.openUrlExternally(url)
        dismiss()
    }

    contentItem: ColumnLayout {
        spacing: Kirigami.Units.smallSpacing

        HoverHandler {
            id: inside
            onHoveredChanged: {
                if (hovered)
                    hideTimer.stop()
                else if (popup.pending === "")
                    hideTimer.restart()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Image {
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Kirigami.Units.iconSizes.small
                visible: status === Image.Ready
                source: page.item ? page.item.icon : ""
                sourceSize.width: Kirigami.Units.iconSizes.small
                sourceSize.height: Kirigami.Units.iconSizes.small
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    text: page.item && page.item.title !== "" && page.item.title !== popup.url ? page.item.title : popup.url
                    font.bold: true
                    elide: Text.ElideRight
                }
                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    text: popup.url
                    font: Kirigami.Theme.smallFont
                    opacity: 0.7
                    elide: Text.ElideMiddle
                }
            }
            PlasmaComponents.ToolButton {
                icon.name: "internet-web-browser"
                onClicked: popup.openInBrowser()
                PlasmaComponents.ToolTip.text: i18n("Open in browser")
                PlasmaComponents.ToolTip.visible: hovered
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: "white"
            clip: true

            Loader {
                id: page
                anchors.fill: parent
                active: popup.loaded && popup.available
                sourceComponent: popup.pageComponent
                onLoaded: item.url = Qt.binding(function () { return popup.url })
            }
            PlasmaComponents.BusyIndicator {
                anchors.centerIn: parent
                running: page.item !== null && page.item.loading
                visible: running
            }
            PlasmaComponents.Label {
                anchors.centerIn: parent
                width: parent.width - Kirigami.Units.largeSpacing * 2
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                visible: page.item !== null && page.item.failed
                text: i18n("The page cannot be loaded")
                color: "black"
            }
            // A click on the preview opens the page in the browser; the wheel still scrolls the preview.
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: popup.openInBrowser()
            }
        }
    }
}
