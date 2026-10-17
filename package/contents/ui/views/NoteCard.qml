import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami
import "keepColors.js" as KeepColors

// One note in the list. Pure presentation: `note` is a plain object from NotesViewModel.
// Clicks, the context menu and drags are handled by the list (NotesScreen), not here: delegates are
// destroyed when they scroll out of view, which must never cut a drag.
Rectangle {
    id: card

    required property var note
    // Show which account the note belongs to (when notes of several accounts are listed together).
    property bool showAccount: false
    property string accountIcon: ""

    // Palette follows the theme; overridable for previews and tests.
    property bool dark: KeepColors.isDark(Kirigami.Theme.backgroundColor)
    readonly property bool colored: KeepColors.has(note.color)
    readonly property color textColor: colored ? KeepColors.textOn(note.color, dark) : Kirigami.Theme.textColor
    readonly property int maxItems: 6
    // Like the editor: open items first, finished ones are only counted.
    readonly property var openItems: card.note.type === "LIST" ? card.note.items.filter(function (i) { return !i.checked }) : []
    readonly property int doneCount: card.note.type === "LIST" ? card.note.items.length - openItems.length : 0

    color: colored ? KeepColors.background(note.color, dark) : Kirigami.Theme.alternateBackgroundColor
    radius: Kirigami.Units.smallSpacing * 2
    border.width: 1
    border.color: colored ? (dark ? Qt.lighter(color, 1.4) : Qt.darker(color, 1.15)) : Qt.alpha(Kirigami.Theme.textColor, 0.2)
    implicitHeight: content.implicitHeight + Kirigami.Units.largeSpacing * 3

    ColumnLayout {
        id: content
        anchors {
            left: parent.left; right: parent.right; top: parent.top
            margins: Kirigami.Units.largeSpacing * 1.5
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
            model: card.openItems.slice(0, card.maxItems)

            PlasmaComponents.Label {
                required property var modelData
                Layout.fillWidth: true
                Layout.leftMargin: modelData.indent * Kirigami.Units.gridUnit
                text: "☐ " + modelData.text
                color: card.textColor
                elide: Text.ElideRight
            }
        }

        PlasmaComponents.Label {
            visible: card.openItems.length > card.maxItems
            text: i18np("+ %1 more item", "+ %1 more items", card.openItems.length - card.maxItems)
            color: card.textColor
            opacity: 0.7
        }

        PlasmaComponents.Label {
            visible: card.doneCount > 0
            text: i18np("☑ %1 done", "☑ %1 done", card.doneCount)
            color: card.textColor
            opacity: 0.7
        }

        RowLayout {
            Layout.fillWidth: true
            visible: card.showAccount && !!card.note.accountName
            spacing: Kirigami.Units.smallSpacing
            opacity: 0.75

            Kirigami.Icon {
                visible: card.accountIcon !== ""
                source: card.accountIcon
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Kirigami.Units.iconSizes.small
            }
            PlasmaComponents.Label {
                Layout.fillWidth: true
                text: card.note.accountName
                color: card.textColor
                font: Kirigami.Theme.smallFont
                elide: Text.ElideRight
            }
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
