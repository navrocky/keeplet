import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.extras as PlasmaExtras

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

    readonly property real rowContentHeight: Math.max(rowMetrics.implicitHeight, Kirigami.Units.iconSizes.smallMedium + Kirigami.Units.smallSpacing * 2)
    // Captions and counts fade while the rail narrows instead of vanishing at once.
    property real textOpacity: collapsed ? 0 : 1
    Behavior on textOpacity {
        NumberAnimation { duration: Kirigami.Units.longDuration; easing.type: Easing.InOutQuad }
    }
    QQC2.Label { id: rowMetrics; text: "Ag"; visible: false }

    // Names of built-in groups are user-facing text, derived from the item kind.
    function groupName(item) {
        if (item.type === "addLabel")
            return i18n("New label\u2026")
        switch (item.kind) {
        case "all": return i18n("All notes")
        case "unlabeled": return i18n("No label")
        case "archive": return i18n("Archive")
        case "trash": return i18n("Trash")
        default: return item.name
        }
    }

    // --- Label management (create from the "New label" row, rename / delete from a label's menu)
    property var _target: null   // {kind: "create"|"rename"|"delete", accountKey, labelKey, labelId, name}

    function _askName(kind, item) {
        var isRename = kind === "rename"
        rail._target = { kind: kind, accountKey: item.accountKey, labelKey: isRename ? item.key.substring("label:".length) : "",
                         labelId: isRename ? item.key.substring(item.key.indexOf("|") + 1) : "", name: item.name || "" }
        nameDialog.title = isRename ? i18n("Rename label") : i18n("New label")
        nameDialog.initialName = isRename ? item.name : ""
        nameDialog.check = function (name) {
            return rail.vm.labelNameError(rail._target.accountKey, name, rail._target.labelId)
        }
        nameDialog.open()
    }

    function _askDelete(item) {
        rail._target = { kind: "delete", accountKey: item.accountKey, labelKey: item.key.substring("label:".length), name: item.name }
        deleteDialog.message = i18n("Delete the label \u201c%1\u201d? The notes stay, they just lose this label.", item.name)
        deleteDialog.open()
    }

    LabelNameDialog {
        id: nameDialog
        onSubmitted: name => {
            if (rail._target.kind === "rename")
                rail.vm.renameLabel(rail._target.labelKey, name)
            else
                rail.vm.createLabel(rail._target.accountKey, name)
        }
    }

    // Confirmation: the same card without the input.
    LabelNameDialog {
        id: deleteDialog
        showInput: false
        title: i18n("Delete label")
        okText: i18n("Delete")
        onSubmitted: rail.vm.deleteLabel(rail._target.labelKey)
    }

    PlasmaExtras.Menu {
        id: labelMenu
        property var item: null

        // Where the label comes from: a label belongs to one account.
        PlasmaExtras.MenuItem {
            enabled: false
            icon: labelMenu.item ? labelMenu.item.providerIcon : ""
            text: labelMenu.item ? i18n("%1 (%2)", labelMenu.item.accountName, labelMenu.item.providerName) : ""
        }
        PlasmaExtras.MenuItem { separator: true }
        PlasmaExtras.MenuItem {
            text: i18n("Rename\u2026")
            icon: "edit-rename"
            onClicked: rail._askName("rename", labelMenu.item)
        }
        PlasmaExtras.MenuItem {
            text: i18n("Delete\u2026")
            icon: "edit-delete"
            onClicked: rail._askDelete(labelMenu.item)
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
            spacing: Kirigami.Units.smallSpacing
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            delegate: QQC2.ItemDelegate {
                id: row
                required property var modelData
                readonly property bool isHeader: modelData.type === "header"
                readonly property bool isAdd: modelData.type === "addLabel"
                readonly property bool editable: modelData.kind === "label" && rail.vm.canEditLabels(modelData.accountKey)

                width: rail.dragNoteKey === "" ? groups.width : groups.width * 0.94
                // Fixed, whatever is shown inside (collapsed or not): rows never change height.
                implicitHeight: rail.rowContentHeight + topPadding + bottomPadding
                // Headers are not selectable (they stay enabled: their "new label" button lives inside).
                hoverEnabled: !isHeader
                // While a note is carried only the drop states are drawn: a selected row would add a second frame.
                highlighted: !isHeader && !isAdd && rail.vm.selected === modelData.key && rail.dragNoteKey === ""
                topPadding: isHeader ? Kirigami.Units.largeSpacing : Kirigami.Units.smallSpacing
                bottomPadding: Kirigami.Units.smallSpacing
                leftPadding: Kirigami.Units.smallSpacing * 2
                rightPadding: Kirigami.Units.smallSpacing * 2

                // A note being dragged over a group that would accept it.
                readonly property bool dropHover: dropArea.containsDrag && dropArea.accepted
                // A note is being carried and this group could take it.
                readonly property bool takesDrag: rail.dragNoteKey !== "" && !isHeader && !!modelData.droppable
                                                  && rail.vm.canDrop(rail.dragNoteKey, modelData.key)

                // The row grows from its left edge; while a note is carried it is narrower so it is not cut off.
                transformOrigin: Item.Left
                scale: dropHover ? 1.05 : (takesDrag ? 1.02 : 1)
                Behavior on scale {
                    NumberAnimation { duration: Kirigami.Units.shortDuration; easing.type: Easing.OutCubic }
                }
                opacity: rail.dragNoteKey === "" || isHeader || isAdd || takesDrag ? 1 : 0.45
                Behavior on opacity {
                    NumberAnimation { duration: Kirigami.Units.shortDuration }
                }

                onClicked: {
                    if (isAdd)
                        rail._askName("create", modelData)
                    else if (!isHeader)
                        rail.vm.select(modelData.key)
                }
                QQC2.ToolTip.text: rail.groupName(modelData) + (isHeader || isAdd ? "" : " (" + modelData.count + ")")
                QQC2.ToolTip.visible: hovered && rail.collapsed
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay

                // Right click or long press on a label: rename / delete.
                TapHandler {
                    enabled: row.editable
                    acceptedButtons: Qt.RightButton
                    onTapped: { labelMenu.item = row.modelData; labelMenu.visualParent = row; labelMenu.openRelative() }
                }
                TapHandler {
                    enabled: row.editable
                    acceptedButtons: Qt.LeftButton
                    onLongPressed: { labelMenu.item = row.modelData; labelMenu.visualParent = row; labelMenu.openRelative() }
                }

                DropArea {
                    id: dropArea
                    anchors.fill: parent
                    enabled: !row.isHeader && !row.isAdd && !!row.modelData.droppable
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

                // A group that can take the carried note is tinted; the one under the pointer gets one frame.
                Rectangle {
                    anchors.fill: parent
                    opacity: row.dropHover ? 1 : (row.takesDrag ? 0.6 : 0)
                    visible: opacity > 0
                    color: Qt.alpha(Kirigami.Theme.highlightColor, row.dropHover ? 0.25 : 0.12)
                    border.width: row.dropHover ? 2 : 0
                    border.color: Kirigami.Theme.highlightColor
                    radius: Kirigami.Units.smallSpacing
                    Behavior on opacity {
                        NumberAnimation { duration: Kirigami.Units.shortDuration }
                    }
                }

                contentItem: RowLayout {
                    spacing: Kirigami.Units.smallSpacing
                    // The same height collapsed or not (the "+" button and the labels come and go), so rows do not jump.
                    implicitHeight: rail.rowContentHeight

                    Kirigami.Icon {
                        source: row.isAdd ? "list-add" : row.modelData.icon
                        Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                        Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                        opacity: row.isHeader || row.isAdd ? 0.7 : 1
                    }

                    QQC2.Label {
                        Layout.fillWidth: true
                        visible: rail.textOpacity > 0
                        text: rail.groupName(row.modelData)
                        elide: Text.ElideRight
                        font.bold: row.isHeader
                        opacity: (row.isHeader ? 0.7 : 1) * rail.textOpacity
                    }

                    // New label of the account the header stands for.
                    QQC2.ToolButton {
                        visible: rail.textOpacity > 0 && row.isHeader && !!row.modelData.canAddLabel
                        opacity: rail.textOpacity
                        icon.name: "list-add"
                        Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium + Kirigami.Units.smallSpacing * 2
                        Layout.preferredWidth: Layout.preferredHeight
                        onClicked: rail._askName("create", row.modelData)
                        QQC2.ToolTip.text: i18n("New label\u2026")
                        QQC2.ToolTip.visible: hovered
                        QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                    }

                    QQC2.Label {
                        visible: rail.textOpacity > 0 && !row.isHeader && !row.isAdd
                        text: row.isHeader || row.isAdd ? "" : row.modelData.count
                        opacity: 0.6 * rail.textOpacity
                    }
                }
            }
        }
    }
}
