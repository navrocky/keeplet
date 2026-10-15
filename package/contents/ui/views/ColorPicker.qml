import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import "keepColors.js" as KeepColors

// Swatch grid for choosing a note color. Presentation only: the owner decides what a pick does.
Item {
    id: picker

    // Color names offered (provider capability `colors`); the first is the "no color" default.
    property var colors: KeepColors.names()
    property string current: "DEFAULT"
    property bool dark: KeepColors.isDark(Kirigami.Theme.backgroundColor)
    property int columns: 6

    signal picked(string name)

    readonly property int swatch: Kirigami.Units.gridUnit * 2

    implicitWidth: grid.implicitWidth
    implicitHeight: grid.implicitHeight

    // Color names are user-facing text, so they are translated here.
    function label(name) {
        switch (name) {
        case "DEFAULT": return i18nc("note color", "Default")
        case "RED": return i18nc("note color", "Red")
        case "ORANGE": return i18nc("note color", "Orange")
        case "YELLOW": return i18nc("note color", "Yellow")
        case "GREEN": return i18nc("note color", "Green")
        case "TEAL": return i18nc("note color", "Teal")
        case "BLUE": return i18nc("note color", "Blue")
        case "CERULEAN": return i18nc("note color", "Dark blue")
        case "PURPLE": return i18nc("note color", "Purple")
        case "PINK": return i18nc("note color", "Pink")
        case "BROWN": return i18nc("note color", "Brown")
        case "GRAY": return i18nc("note color", "Gray")
        default: return name
        }
    }

    GridLayout {
        id: grid
        columns: picker.columns
        rowSpacing: Kirigami.Units.smallSpacing
        columnSpacing: Kirigami.Units.smallSpacing

        Repeater {
            model: picker.colors

            Rectangle {
                id: swatch
                required property string modelData
                readonly property bool isCurrent: modelData === picker.current
                readonly property string shade: KeepColors.background(modelData, picker.dark)

                Layout.preferredWidth: picker.swatch
                Layout.preferredHeight: picker.swatch
                radius: width / 2
                color: shade !== "" ? shade : Kirigami.Theme.backgroundColor
                border.width: isCurrent ? 3 : 1
                border.color: isCurrent ? Kirigami.Theme.highlightColor : Qt.alpha(Kirigami.Theme.textColor, 0.3)

                // "No color" is drawn as an empty circle with a slash.
                Kirigami.Icon {
                    anchors.centerIn: parent
                    visible: swatch.shade === ""
                    source: "dialog-cancel"
                    width: Kirigami.Units.iconSizes.small
                    height: width
                    opacity: 0.6
                }

                Kirigami.Icon {
                    anchors.centerIn: parent
                    visible: swatch.isCurrent && swatch.shade !== ""
                    source: "checkmark"
                    width: Kirigami.Units.iconSizes.small
                    height: width
                    color: KeepColors.textOn(swatch.modelData, picker.dark)
                }

                TapHandler {
                    onTapped: picker.picked(swatch.modelData)
                    cursorShape: Qt.PointingHandCursor
                }

                QQC2.ToolTip.text: picker.label(modelData)
                QQC2.ToolTip.visible: hover.hovered
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                HoverHandler { id: hover }
            }
        }
    }
}
