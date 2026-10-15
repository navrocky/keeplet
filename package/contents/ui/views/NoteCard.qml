import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami
import "keepColors.js" as KeepColors

// One note in the list. Pure presentation: `note` is a plain object from NotesViewModel.
Rectangle {
    id: card

    required property var note

    signal clicked()

    readonly property bool colored: KeepColors.has(note.color)
    // Keep's pastel colors are light in both themes, so text on them must be dark.
    readonly property color textColor: colored ? KeepColors.TEXT_ON_COLOR : Kirigami.Theme.textColor
    readonly property int maxItems: 6

    color: colored ? KeepColors.background(note.color) : Kirigami.Theme.alternateBackgroundColor
    radius: Kirigami.Units.smallSpacing * 2
    border.width: 1
    border.color: colored ? Qt.darker(color, 1.15) : Qt.alpha(Kirigami.Theme.textColor, 0.2)
    implicitHeight: content.implicitHeight + Kirigami.Units.largeSpacing * 2

    TapHandler {
        onTapped: card.clicked()
        cursorShape: Qt.PointingHandCursor
    }

    ColumnLayout {
        id: content
        anchors {
            left: parent.left; right: parent.right; top: parent.top
            margins: Kirigami.Units.largeSpacing
        }
        spacing: Kirigami.Units.smallSpacing

        RowLayout {
            Layout.fillWidth: true
            visible: card.note.title !== "" || card.note.pinned

            PlasmaComponents.Label {
                Layout.fillWidth: true
                text: card.note.title
                font.bold: true
                color: card.textColor
                elide: Text.ElideRight
                maximumLineCount: 2
                wrapMode: Text.Wrap
            }
            Kirigami.Icon {
                visible: card.note.pinned
                source: "pin"
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Kirigami.Units.iconSizes.small
            }
        }

        PlasmaComponents.Label {
            Layout.fillWidth: true
            visible: card.note.type === "NOTE" && card.note.text !== ""
            text: card.note.text
            color: card.textColor
            wrapMode: Text.Wrap
            elide: Text.ElideRight
            maximumLineCount: 8
        }

        Repeater {
            model: card.note.type === "LIST" ? card.note.items.slice(0, card.maxItems) : []

            PlasmaComponents.Label {
                required property var modelData
                Layout.fillWidth: true
                Layout.leftMargin: modelData.indent * Kirigami.Units.gridUnit
                text: (modelData.checked ? "☑ " : "☐ ") + modelData.text
                color: card.textColor
                opacity: modelData.checked ? 0.6 : 1
                font.strikeout: modelData.checked
                elide: Text.ElideRight
            }
        }

        PlasmaComponents.Label {
            visible: card.note.type === "LIST" && card.note.items.length > card.maxItems
            text: i18np("+ %1 more item", "+ %1 more items", card.note.items.length - card.maxItems)
            color: card.textColor
            opacity: 0.7
        }

        Flow {
            Layout.fillWidth: true
            visible: card.note.labels.length > 0
            spacing: Kirigami.Units.smallSpacing

            Repeater {
                model: card.note.labels

                Rectangle {
                    required property var modelData
                    implicitWidth: chip.implicitWidth + Kirigami.Units.smallSpacing * 2
                    implicitHeight: chip.implicitHeight + 2
                    radius: height / 2
                    color: Qt.alpha(card.textColor, 0.12)

                    PlasmaComponents.Label {
                        id: chip
                        anchors.centerIn: parent
                        text: parent.modelData.name
                        color: card.textColor
                        font: Kirigami.Theme.smallFont
                    }
                }
            }
        }
    }
}
