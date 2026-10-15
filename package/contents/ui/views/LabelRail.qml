import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

// Left rail: account switcher (several accounts only) and groups. Collapses to icons.
// Presentation only: the item list, counts and selection live in NotesViewModel.
Item {
    id: rail

    required property var vm
    property bool multiAccount: false
    // The note being dragged ("" when none): groups that can take it grow, the others dim.
    property string dragNoteKey: ""

    readonly property int expandedWidth: Kirigami.Units.gridUnit * 10
    readonly property int collapsedWidth: Kirigami.Units.iconSizes.smallMedium + Kirigami.Units.largeSpacing * 2 + 4
    readonly property bool collapsed: vm.railCollapsed

    implicitWidth: collapsed ? collapsedWidth : expandedWidth
    Behavior on implicitWidth {
        NumberAnimation { duration: Kirigami.Units.longDuration; easing.type: Easing.InOutQuad }
    }
    clip: true

    // Names of built-in groups are user-facing text, derived from the item kind.
    function groupName(item) {
        switch (item.kind) {
        case "all": return i18n("All notes")
        case "unlabeled": return i18n("No label")
        case "archive": return i18n("Archive")
        case "trash": return i18n("Trash")
        default: return item.name
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Kirigami.Units.smallSpacing

        Flow {
            Layout.fillWidth: true
            visible: rail.multiAccount
            spacing: 0

            Repeater {
                model: rail.vm.accountTabs

                QQC2.ToolButton {
                    required property var modelData
                    checkable: true
                    checked: rail.vm.accountFilter === modelData.key
                    // "All accounts" gets an icon; accounts get their initial, since two accounts of
                    // one provider share an icon (the full name is in the tooltip).
                    icon.name: modelData.key === "" ? "view-list-icons" : ""
                    text: modelData.key === "" ? "" : modelData.name.charAt(0).toUpperCase()
                    display: modelData.key === "" ? QQC2.AbstractButton.IconOnly : QQC2.AbstractButton.TextOnly
                    onClicked: rail.vm.selectAccount(modelData.key)
                    QQC2.ToolTip.text: modelData.key === "" ? i18n("All accounts") : modelData.name
                    QQC2.ToolTip.visible: hovered
                }
            }
        }

        ListView {
            id: groups
            Layout.fillWidth: true
            Layout.fillHeight: true
            model: rail.vm.rail
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            delegate: QQC2.ItemDelegate {
                id: row
                required property var modelData
                readonly property bool isHeader: modelData.type === "header"

                width: groups.width
                // Headers are not selectable.
                enabled: !isHeader
                highlighted: !isHeader && rail.vm.selected === modelData.key
                topPadding: isHeader ? Kirigami.Units.largeSpacing : Kirigami.Units.smallSpacing
                bottomPadding: Kirigami.Units.smallSpacing
                leftPadding: Kirigami.Units.smallSpacing * 2
                rightPadding: Kirigami.Units.smallSpacing * 2

                // A note being dragged over a group that would accept it.
                readonly property bool dropHover: dropArea.containsDrag && dropArea.accepted
                // A note is being carried and this group could take it.
                readonly property bool takesDrag: rail.dragNoteKey !== "" && !isHeader && modelData.droppable
                                                  && rail.vm.canDrop(rail.dragNoteKey, modelData.key)

                transformOrigin: Item.Left
                scale: dropHover ? 1.1 : (takesDrag ? 1.03 : 1)
                opacity: rail.dragNoteKey === "" || isHeader || takesDrag ? 1 : 0.45
                Behavior on scale {
                    NumberAnimation { duration: Kirigami.Units.shortDuration; easing.type: Easing.OutCubic }
                }
                Behavior on opacity {
                    NumberAnimation { duration: Kirigami.Units.shortDuration }
                }

                onClicked: rail.vm.select(modelData.key)
                QQC2.ToolTip.text: rail.groupName(modelData) + (isHeader ? "" : " (" + modelData.count + ")")
                QQC2.ToolTip.visible: hovered && rail.collapsed
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay

                DropArea {
                    id: dropArea
                    anchors.fill: parent
                    enabled: !row.isHeader && row.modelData.droppable
                    // Whether the note under the pointer may go here; set when it enters.
                    property bool accepted: false
                    onEntered: drag => {
                        accepted = rail.vm.canDrop(drag.source.noteKey, row.modelData.key)
                        drag.accepted = accepted
                    }
                    onExited: accepted = false
                    onDropped: drop => {
                        if (accepted && rail.vm.dropNote(drop.source.noteKey, row.modelData.key))
                            drop.accept()
                        accepted = false
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    visible: row.dropHover
                    color: Qt.alpha(Kirigami.Theme.highlightColor, 0.2)
                    border.width: 2
                    border.color: Kirigami.Theme.highlightColor
                    radius: Kirigami.Units.smallSpacing
                }

                contentItem: RowLayout {
                    spacing: Kirigami.Units.smallSpacing

                    Kirigami.Icon {
                        source: row.modelData.icon
                        Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                        Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                        opacity: row.isHeader ? 0.7 : 1
                    }

                    QQC2.Label {
                        Layout.fillWidth: true
                        visible: !rail.collapsed
                        text: rail.groupName(row.modelData)
                        elide: Text.ElideRight
                        font.bold: row.isHeader
                        opacity: row.isHeader ? 0.7 : 1
                    }

                    QQC2.Label {
                        visible: !rail.collapsed && !row.isHeader
                        text: row.isHeader ? "" : row.modelData.count
                        opacity: 0.6
                    }
                }
            }
        }
    }
}
