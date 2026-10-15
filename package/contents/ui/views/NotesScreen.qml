import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import QtQuick.Controls as QQC2
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

// Notes screen. Presentation only: reads and commands go through the ViewModels.
ColumnLayout {
    id: view

    required property var vm          // NotesViewModel
    required property var accountsVm  // AccountsViewModel

    spacing: Kirigami.Units.smallSpacing

    function errorText(error) {
        var who = view.accountsVm.multiAccount ? error.displayName + ": " : ""
        switch (error.kind) {
        case "network": return who + i18n("Can't reach the service. Showing saved notes.")
        case "auth": return who + i18n("The saved session is no longer valid. Please sign in again.")
        case "unauthorized": return who + i18n("The service refused the session. Try again in a moment.")
        default: return who + i18n("Sync failed: %1", error.detail)
        }
    }

    function actionText(action) {
        if (!action)
            return ""
        switch (action.kind) {
        case "trashed": return i18n("Note moved to the trash.")
        case "archived": return i18n("Note archived.")
        case "unarchived": return i18n("Note unarchived.")
        case "labeled": return i18n("Added to \u201c%1\u201d.", action.label)
        case "unlabeled": return i18n("Removed from all labels.")
        default: return ""
        }
    }

    function dragLayerParent() {
        if (QQC2.Overlay.overlay)
            return QQC2.Overlay.overlay
        return view.Window.window ? view.Window.window.contentItem : view
    }

    // --- drag of a note onto a group: the ghost follows the pointer, groups accept the drop
    function beginDrag(note, card) {
        ghost.noteKey = note.key
        ghost.title = note.title !== "" ? note.title : i18n("Untitled note")
        ghost.width = Math.min(card.width, Kirigami.Units.gridUnit * 12)
        ghostLayer.visible = true
        ghost.visible = true
    }
    function moveDrag(scenePosition) {
        var p = ghostLayer.mapFromItem(null, scenePosition.x, scenePosition.y)
        ghost.x = p.x - ghost.width / 2
        ghost.y = p.y - ghost.height / 2
    }
    function endDrag() {
        if (!ghost.visible)
            return
        ghost.Drag.drop()
        ghost.visible = false
        ghostLayer.visible = false
        ghost.noteKey = ""
    }

    RowLayout {
        Layout.fillWidth: true

        PlasmaComponents.ToolButton {
            visible: view.vm.railVisible
            icon.name: view.vm.railCollapsed ? "sidebar-expand" : "sidebar-collapse"
            onClicked: view.vm.railCollapsed = !view.vm.railCollapsed
            PlasmaComponents.ToolTip.text: view.vm.railCollapsed ? i18n("Show group names") : i18n("Collapse groups")
            PlasmaComponents.ToolTip.visible: hovered
        }

        PlasmaComponents.TextField {
            Layout.fillWidth: true
            placeholderText: i18n("Search notes")
            onTextChanged: view.vm.searchText = text
        }

        PlasmaComponents.ToolButton {
            id: addButton
            icon.name: "list-add"
            enabled: view.vm.canCreate
            onClicked: addMenu.popup(addButton, 0, addButton.height)
            PlasmaComponents.ToolTip.text: i18n("New note")
            PlasmaComponents.ToolTip.visible: hovered

            QQC2.Menu {
                id: addMenu
                QQC2.MenuItem {
                    text: i18n("New note")
                    icon.name: "document-new"
                    onTriggered: view.vm.openNewNote("NOTE")
                }
                QQC2.MenuItem {
                    text: i18n("New list")
                    icon.name: "view-list-details"
                    onTriggered: view.vm.openNewNote("LIST")
                }
            }
        }

        PlasmaComponents.ToolButton {
            icon.name: "view-refresh"
            enabled: !view.vm.syncing
            onClicked: view.vm.refresh()
            PlasmaComponents.ToolTip.text: i18n("Sync now")
            PlasmaComponents.ToolTip.visible: hovered
        }

        PlasmaComponents.ToolButton {
            id: menuButton
            icon.name: "application-menu"
            onClicked: menu.popup(menuButton, 0, menuButton.height)

            QQC2.Menu {
                id: menu

                QQC2.MenuItem {
                    text: i18n("Add account…")
                    icon.name: "list-add"
                    onTriggered: view.accountsVm.requestSignIn()
                }
                QQC2.MenuSeparator {}

                Instantiator {
                    model: view.accountsVm.accounts
                    delegate: QQC2.MenuItem {
                        required property var modelData
                        text: i18n("Sign out %1", modelData.displayName)
                        icon.name: "system-log-out"
                        onTriggered: view.accountsVm.remove(modelData.key)
                    }
                    onObjectAdded: (index, object) => menu.addItem(object)
                    onObjectRemoved: (index, object) => menu.removeItem(object)
                }
            }
        }
    }

    PlasmaComponents.ProgressBar {
        Layout.fillWidth: true
        indeterminate: true
        visible: view.vm.syncing
    }

    Repeater {
        model: view.vm.errors

        Kirigami.InlineMessage {
            required property var modelData
            Layout.fillWidth: true
            type: Kirigami.MessageType.Warning
            text: view.errorText(modelData)
            visible: true
            actions: modelData.kind === "auth" ? [signInAction] : []

            Kirigami.Action {
                id: signInAction
                text: i18n("Sign In")
                onTriggered: view.accountsVm.requestSignIn()
            }
        }
    }

    // "Undo" notice for the last trash/archive/label action; hides itself after a while.
    Kirigami.InlineMessage {
        id: undoNotice
        Layout.fillWidth: true
        type: Kirigami.MessageType.Information
        visible: view.vm.lastAction !== null
        text: view.actionText(view.vm.lastAction)
        actions: [
            Kirigami.Action {
                text: i18n("Undo")
                icon.name: "edit-undo"
                onTriggered: view.vm.undoLast()
            }
        ]
    }

    Timer {
        id: noticeTimer
        interval: 7000
        running: view.vm.lastAction !== null
        onTriggered: view.vm.dismissAction()
    }
    Connections {
        target: view.vm
        function onLastActionChanged() {
            if (view.vm.lastAction !== null)
                noticeTimer.restart()
        }
    }

    RowLayout {
        Layout.fillWidth: true
        visible: view.vm.selected === "trash" && view.vm.notes.length > 0

        PlasmaComponents.Label {
            Layout.fillWidth: true
            opacity: 0.7
            text: i18n("Notes in the trash can be restored or deleted for good.")
            wrapMode: Text.Wrap
        }
        PlasmaComponents.Button {
            icon.name: "edit-delete"
            text: i18n("Empty trash")
            onClicked: confirmEmpty.open()
        }
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: Kirigami.Units.smallSpacing

        LabelRail {
            Layout.fillHeight: true
            visible: view.vm.railVisible
            vm: view.vm
            multiAccount: view.accountsVm.multiAccount
        }

        PlasmaComponents.ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ListView {
                id: list
                model: view.vm.notes
                spacing: Kirigami.Units.smallSpacing
                clip: true

                delegate: NoteCard {
                    id: card
                    required property var modelData
                    width: list.width
                    note: modelData
                    onClicked: view.vm.openNote(modelData.key)
                    onContextRequested: position => noteMenu.openFor(modelData, card, position)
                    onDragStarted: view.beginDrag(modelData, card)
                    onDragMoved: scenePosition => view.moveDrag(scenePosition)
                    onDragFinished: view.endDrag()
                }

                PlasmaComponents.Label {
                    anchors.centerIn: parent
                    width: parent.width - Kirigami.Units.gridUnit * 2
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    opacity: 0.7
                    visible: list.count === 0 && !view.vm.syncing
                    text: !view.vm.loaded ? i18n("Nothing here yet.")
                          : view.vm.searchText !== "" ? i18n("No notes match your search.")
                          : i18n("No notes.")
                }
            }
        }
    }

    // Overlays -------------------------------------------------------------------------------

    // Floats above everything while a note is dragged; DropAreas in the rail receive its Drag events.
    Item {
        id: ghostLayer
        // Not a child of the layout above; the window's overlay (or content item) covers the whole popup.
        // Set once: binding to it would loop, since the overlay is found through this item's own window.
        Component.onCompleted: parent = view.dragLayerParent()
        // Invisible (and so not in the way of any pointer event) except while a note is dragged.
        visible: false
        x: 0
        y: 0
        width: parent ? parent.width : 0
        height: parent ? parent.height : 0

        Rectangle {
            id: ghost
            property string noteKey: ""
            property string title: ""
            visible: false
            z: 1000
            height: ghostLabel.implicitHeight + Kirigami.Units.largeSpacing * 2
            radius: Kirigami.Units.smallSpacing * 2
            color: Kirigami.Theme.backgroundColor
            border.color: Kirigami.Theme.highlightColor
            border.width: 2
            opacity: 0.9

            Drag.active: visible
            Drag.source: ghost
            Drag.hotSpot: Qt.point(width / 2, height / 2)

            PlasmaComponents.Label {
                id: ghostLabel
                anchors.fill: parent
                anchors.margins: Kirigami.Units.largeSpacing
                text: ghost.title
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
            }
        }
    }

    QQC2.Menu {
        id: noteMenu
        property var note: null
        readonly property bool inTrash: note !== null && note.trashed
        readonly property var colors: note !== null && view.vm.capabilities(note.accountKey)
                                      ? view.vm.capabilities(note.accountKey).colors : []

        function openFor(n, item, position) {
            note = n
            popup(item, position.x, position.y)
        }

        QQC2.MenuItem {
            visible: !noteMenu.inTrash
            height: visible ? implicitHeight : 0
            text: noteMenu.note !== null && noteMenu.note.pinned ? i18n("Unpin") : i18n("Pin")
            icon.name: "pin"
            onTriggered: view.vm.setPinned(noteMenu.note.key, !noteMenu.note.pinned)
        }
        QQC2.MenuItem {
            visible: !noteMenu.inTrash && noteMenu.colors.length > 0
            height: visible ? implicitHeight : 0
            text: i18n("Color…")
            icon.name: "color-management"
            onTriggered: colorPopup.openFor(noteMenu.note)
        }
        QQC2.MenuItem {
            visible: !noteMenu.inTrash
            height: visible ? implicitHeight : 0
            text: noteMenu.note !== null && noteMenu.note.archived ? i18n("Unarchive") : i18n("Archive")
            icon.name: "archive-insert"
            onTriggered: view.vm.archiveNote(noteMenu.note.key, !noteMenu.note.archived)
        }
        QQC2.MenuItem {
            visible: !noteMenu.inTrash
            height: visible ? implicitHeight : 0
            text: i18n("Move to trash")
            icon.name: "user-trash"
            onTriggered: view.vm.trashNote(noteMenu.note.key)
        }
        QQC2.MenuItem {
            visible: noteMenu.inTrash
            height: visible ? implicitHeight : 0
            text: i18n("Restore")
            icon.name: "edit-undo"
            onTriggered: view.vm.restoreNote(noteMenu.note.key)
        }
        QQC2.MenuItem {
            visible: noteMenu.inTrash
            height: visible ? implicitHeight : 0
            text: i18n("Delete forever…")
            icon.name: "edit-delete"
            onTriggered: confirmDelete.openFor(noteMenu.note)
        }
    }

    QQC2.Popup {
        id: colorPopup
        property var note: null
        parent: view
        x: Math.round((view.width - width) / 2)
        y: Math.round(view.height / 3)
        padding: Kirigami.Units.largeSpacing
        closePolicy: QQC2.Popup.CloseOnEscape | QQC2.Popup.CloseOnPressOutside

        function openFor(n) {
            note = n
            open()
        }

        contentItem: ColorPicker {
            colors: colorPopup.note !== null && view.vm.capabilities(colorPopup.note.accountKey)
                    ? view.vm.capabilities(colorPopup.note.accountKey).colors : []
            current: colorPopup.note !== null ? colorPopup.note.color : "DEFAULT"
            onPicked: name => {
                view.vm.setColor(colorPopup.note.key, name)
                colorPopup.close()
            }
        }
    }

    QQC2.Dialog {
        id: confirmDelete
        property var note: null
        parent: view
        anchors.centerIn: parent
        modal: true
        title: i18n("Delete forever?")
        width: Math.min(view.width - Kirigami.Units.gridUnit * 2, Kirigami.Units.gridUnit * 20)
        standardButtons: QQC2.Dialog.Yes | QQC2.Dialog.No
        function openFor(n) {
            note = n
            open()
        }
        contentItem: PlasmaComponents.Label {
            wrapMode: Text.Wrap
            text: i18n("This note will be deleted permanently and can't be restored.")
        }
        onAccepted: view.vm.deleteForever(note.key)
    }

    QQC2.Dialog {
        id: confirmEmpty
        parent: view
        anchors.centerIn: parent
        modal: true
        title: i18n("Empty trash?")
        width: Math.min(view.width - Kirigami.Units.gridUnit * 2, Kirigami.Units.gridUnit * 20)
        standardButtons: QQC2.Dialog.Yes | QQC2.Dialog.No
        contentItem: PlasmaComponents.Label {
            wrapMode: Text.Wrap
            text: i18n("All notes in the trash will be deleted permanently and can't be restored.")
        }
        onAccepted: view.vm.emptyTrash()
    }
}
