import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import QtQuick.Controls as QQC2
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid

// Notes screen. Presentation only: reads and commands go through the ViewModels.
// The root is a plain Item: the drag layer must be a sibling of the layout, never a child of it.
Item {
    id: view

    required property var vm          // NotesViewModel
    required property var accountsVm  // AccountsViewModel

    // One gap everywhere: between the toolbar and the list, and between the rail and the list.
    readonly property int gap: Kirigami.Units.largeSpacing

    // Accounts are managed in the widget's settings dialog.
    function openSettings() {
        Plasmoid.internalAction("configure").trigger()
    }

    function errorText(error) {
        var who = view.accountsVm.multiAccount ? error.displayName + ": " : ""
        switch (error.kind) {
        case "network": return who + i18n("Can't reach the service. Showing saved notes.")
        case "auth": return who + i18n("The saved session is no longer valid. Please sign in again.")
        case "storage": return who + i18n("The stored notes could not be read. Editing is disabled to protect them.")
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
        case "moved": return i18n("Note moved.")
        default: return ""
        }
    }

    // --- drag of a note onto a group: the ghost follows the pointer, groups accept the drop
    function beginDrag(note, card, scenePosition) {
        var origin = card.mapToItem(view, 0, 0)
        var pointer = view.mapFromItem(null, scenePosition.x, scenePosition.y)
        dragHeight = card.height
        dragLayer.begin(note.key, note.title !== "" ? note.title : i18n("Untitled note"),
                        pointer.x, pointer.y, origin.x, origin.y, card.width, card.height, card.color)
        placeholderLive = false
        updateInsertion()      // the placeholder is there at once, in the carried card's own place
        placeholderLive = true
    }
    function moveDrag(scenePosition) {
        var p = view.mapFromItem(null, scenePosition.x, scenePosition.y)
        dragLayer.moveTo(p.x, p.y)
        updateInsertion()
    }
    function endDrag() {
        var key = dragLayer.noteKey
        var index = insertIndex
        var action = dragLayer.drop()          // a group in the rail may take the note
        insertIndex = -1
        carriedIndex = -1
        // Not taken by a group: if it was held over the list, put it there (manual order).
        // The cards are already where the drag put them: the reorder must not animate them a second time.
        reordering = true
        settle.restart()
        if (action === Qt.IgnoreAction && index >= 0 && key !== "")
            view.vm.moveNote(key, index)
    }

    // --- manual order: where the carried note would be inserted
    // Slots never change their height: the cards between the old and the new place slide by the size of the
    // carried card and a placeholder of that size marks the place.
    property int carriedIndex: -1     // list index of the carried note
    property int insertIndex: -1      // where it would go, as an index of the list without it (-1: not over the list)
    property real placeholderY: 0     // content y of the placeholder (set by the slot it lands on, see the delegate)
    property bool reordering: false
    Timer { id: settle; interval: 150; onTriggered: view.reordering = false }
    property bool placeholderLive: false   // the placeholder glides (not at the start, where it just appears)
    property real dragHeight: 0       // height of the carried card = size of the placeholder

    function updateInsertion() {
        var index = -1
        var carried = -1
        if (dragLayer.active && view.vm.reorderEnabled) {
            var p = list.mapFromItem(dragLayer, dragLayer.pointer.x, dragLayer.pointer.y)
            var inside = p.x >= 0 && p.x <= list.width && p.y >= -scrollZone && p.y <= list.height + scrollZone
            if (inside) {
                var c = list.contentItem.mapFromItem(dragLayer, dragLayer.pointer.x, dragLayer.pointer.y)
                var notes = view.vm.notes
                for (var i = 0; i < notes.length; i++) {
                    if (notes[i].key === dragLayer.noteKey)
                        carried = i
                }
                // First card whose natural centre (slots do not move) is below the pointer: insert in front of it.
                var found = -1
                var lastSeen = -1
                for (var j = 0; j < list.count; j++) {
                    var slot = list.itemAtIndex(j)
                    if (!slot || j === carried)
                        continue
                    lastSeen = j
                    if (c.y < slot.y + slot.height / 2) {
                        found = j
                        break
                    }
                }
                if (found < 0 && lastSeen >= 0)
                    found = lastSeen + 1
                if (found >= 0) {
                    index = carried >= 0 && found > carried ? found - 1 : found
                    if (!view.vm.canMoveTo(dragLayer.noteKey, index))
                        index = -1
                }
            }
        }
        carriedIndex = carried
        insertIndex = index
    }

    // --- scrolling the list while a card is held near its top or bottom edge
    readonly property real scrollZone: Kirigami.Units.gridUnit * 2.5
    readonly property real scrollSpeed: Kirigami.Units.gridUnit * 0.8   // px per tick at the very edge

    function autoScrollStep() {
        if (!dragLayer.active)
            return
        var p = list.mapFromItem(dragLayer, dragLayer.pointer.x, dragLayer.pointer.y)
        var h = list.height
        var v = 0
        if (p.y < scrollZone)
            v = -Math.min(1, (scrollZone - p.y) / scrollZone)       // above the list counts as the very edge
        else if (p.y > h - scrollZone)
            v = Math.min(1, (p.y - (h - scrollZone)) / scrollZone)
        if (v === 0)
            return
        var minY = list.originY
        var maxY = list.originY + Math.max(0, list.contentHeight - h)
        list.contentY = Math.max(minY, Math.min(maxY, list.contentY + v * scrollSpeed))
        updateInsertion()          // the cards moved under a pointer that did not
    }

    Timer {
        interval: 16
        repeat: true
        running: dragLayer.active
        onTriggered: view.autoScrollStep()
    }

    // A drag must not outlive the situation it started in.
    Connections {
        target: view.vm
        function onSelectedChanged() { dragLayer.cancel() }
        function onAccountFilterChanged() { dragLayer.cancel() }
        function onCurrentNoteKeyChanged() { dragLayer.cancel() }
    }

    // Scrolling by wheel or the scroll bar while a card is carried moves the cards under the pointer.
    Connections {
        target: list
        function onContentYChanged() {
            if (dragLayer.active)
                view.updateInsertion()
        }
    }

    // A cancelled drag leaves no gap behind.
    Connections {
        target: dragLayer
        function onCancelled() {
            view.insertIndex = -1
            view.carriedIndex = -1
        }
    }

    // "Undo" notice for the last trash/archive/label action; hides itself after a while. It floats over the
    // bottom of the list, so showing or hiding it never moves the notes; it fades and slides in and out.
    property string noticeText: ""
    Connections {
        target: view.vm
        function onLastActionChanged() {
            // Keep the text while the notice fades out.
            if (view.vm.lastAction !== null)
                view.noticeText = view.actionText(view.vm.lastAction)
        }
    }
    Kirigami.InlineMessage {
        id: undoNotice
        z: 50
        anchors {
            left: parent.left; right: parent.right; bottom: parent.bottom
            margins: view.gap
        }
        type: Kirigami.MessageType.Information
        showCloseButton: false
        visible: view.vm.lastAction !== null
        opacity: visible ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: Kirigami.Units.longDuration; easing.type: Easing.InOutQuad }
        }
        text: view.noticeText
        actions: [
            Kirigami.Action {
                text: i18n("Undo")
                icon.name: "edit-undo"
                onTriggered: view.vm.undoLast()
            }
        ]
    }

    ColumnLayout {
        id: content
        anchors.fill: parent
        spacing: view.gap

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
                onClicked: { addMenu.visualParent = addButton; addMenu.openRelative() }
                PlasmaComponents.ToolTip.text: i18n("New note")
                PlasmaComponents.ToolTip.visible: hovered

                PlasmaExtras.Menu {
                    id: addMenu
                    PlasmaExtras.MenuItem {
                        text: i18n("New note")
                        icon: "document-new"
                        onClicked: view.vm.openNewNote("NOTE")
                    }
                    PlasmaExtras.MenuItem {
                        text: i18n("New list")
                        icon: "view-list-details"
                        onClicked: view.vm.openNewNote("LIST")
                    }
                }
            }

            PlasmaComponents.ToolButton {
                id: syncButton
                icon.name: "view-refresh"
                onClicked: {
                    if (!view.vm.syncing)
                        view.vm.refresh()
                }
                PlasmaComponents.ToolTip.text: i18n("Sync now")
                PlasmaComponents.ToolTip.visible: hovered

                // The icon turns while a sync runs; nothing is added to the layout, so the list never jumps.
                RotationAnimator {
                    target: syncButton.contentItem
                    running: view.vm.syncing
                    from: 0
                    to: 360
                    duration: 1000
                    loops: Animation.Infinite
                    onRunningChanged: {
                        if (!running && target)
                            target.rotation = 0
                    }
                }
            }

            PlasmaComponents.ToolButton {
                id: menuButton
                icon.name: "application-menu"
                onClicked: { menu.visualParent = menuButton; menu.openRelative() }

                PlasmaExtras.Menu {
                    id: menu

                    PlasmaExtras.MenuItem {
                        text: i18n("Settings…")
                        icon: "configure"
                        onClicked: view.openSettings()
                    }
                }
            }
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
                    text: i18n("Open Settings")
                    onTriggered: view.openSettings()
                }
            }
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
            spacing: view.gap

            LabelRail {
                Layout.fillHeight: true
                visible: view.vm.railVisible
                vm: view.vm
                multiAccount: view.accountsVm.multiAccount
                dragNoteKey: dragLayer.active ? dragLayer.noteKey : ""
            }

            // Switching the group: the new list slides in from the rail side while the old one (a frozen
            // snapshot of the list, `ghost`) slides out to the right and fades.
            Item {
                id: listHost
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                readonly property real slideDistance: Kirigami.Units.gridUnit * 2
                // The ghost keeps copying the list (nearly invisible) so that it holds the previous content
                // when the group changes; an item with opacity 0 would not be rendered at all.
                readonly property real idleGhost: 0.003

                ShaderEffectSource {
                    id: ghost
                    anchors.fill: parent
                    sourceItem: listScroll
                    live: true
                    opacity: listHost.idleGhost
                    transform: Translate { id: ghostSlide }
                }

                ParallelAnimation {
                    id: slideIn
                    NumberAnimation {
                        target: slide; property: "x"; from: -listHost.slideDistance; to: 0
                        duration: Kirigami.Units.longDuration; easing.type: Easing.OutCubic
                    }
                    NumberAnimation {
                        target: listScroll; property: "opacity"; from: 0; to: 1
                        duration: Kirigami.Units.longDuration; easing.type: Easing.OutCubic
                    }
                    NumberAnimation {
                        target: ghostSlide; property: "x"; from: 0; to: listHost.slideDistance
                        duration: Kirigami.Units.longDuration; easing.type: Easing.OutCubic
                    }
                    NumberAnimation {
                        target: ghost; property: "opacity"; from: 1; to: listHost.idleGhost
                        duration: Kirigami.Units.longDuration; easing.type: Easing.OutCubic
                    }
                    onFinished: ghost.live = true
                }
                Connections {
                    target: view.vm
                    function onSelectedChanged() {
                        ghost.live = false     // freeze what is on screen now, before the model changes
                        slideIn.restart()
                    }
                }

                PlasmaComponents.ScrollView {
                    id: listScroll
                    anchors.fill: parent
                    clip: true

                    // Switching the group: the list slides out of the rail to the right.
                    transform: Translate { id: slide }
                    ListView {
                        id: list
                        model: view.vm.notes
                        spacing: Kirigami.Units.largeSpacing
                        clip: true
                        interactive: !hold.armed

                        // Pointer handling lives here, on the list, because it must outlive the cards: a delegate is
                        // destroyed when it scrolls out of view, and a drag has to survive that.
                        // (Handlers declared in a ListView work in content coordinates, as ListView.itemAt expects.)
                        TapHandler {
                            acceptedButtons: Qt.LeftButton
                            cursorShape: Qt.PointingHandCursor
                            onTapped: eventPoint => {
                                var slot = list.itemAt(eventPoint.position.x, eventPoint.position.y)
                                if (slot && !hold.carried)
                                    view.vm.openNote(slot.modelData.key)
                            }
                        }

                        TapHandler {
                            acceptedButtons: Qt.RightButton
                            onTapped: eventPoint => {
                                var slot = list.itemAt(eventPoint.position.x, eventPoint.position.y)
                                if (slot)
                                    noteMenu.openFor(slot.modelData, list.contentItem,
                                                     eventPoint.position)
                            }
                        }

                        // A card is picked up by holding it still for a moment; after that it follows the pointer in any
                        // direction (towards the rail to give it a group, up/down to put it in another place).
                        // Moving before the hold is over is a scroll.
                        PointHandler {
                            id: hold
                            acceptedButtons: Qt.LeftButton
                            property bool armed: false
                            property bool moved: false
                            property string pressedKey: ""    // card under a press that may still turn into a hold
                            property bool carried: false      // this press picked a card up: its release is not a tap
                            readonly property real slop: Kirigami.Units.gridUnit * 0.6

                            onActiveChanged: {
                                if (active) {
                                    moved = false
                                    carried = false
                                    var pressed = list.itemAt(point.pressPosition.x, point.pressPosition.y)
                                    pressedKey = pressed ? pressed.modelData.key : ""
                                } else {
                                    pressedKey = ""
                                }
                                if (!active && armed) {
                                    armed = false
                                    view.endDrag()
                                }
                            }
                            onPointChanged: {
                                if (!active)
                                    return
                                if (armed) {
                                    view.moveDrag(point.scenePosition)
                                } else if (Math.abs(point.position.x - point.pressPosition.x) > slop
                                           || Math.abs(point.position.y - point.pressPosition.y) > slop) {
                                    moved = true
                                    pressedKey = ""
                                }
                            }
                        }

                        Timer {
                            interval: 450
                            running: hold.active && !hold.armed && !hold.moved
                            onTriggered: {
                                var slot = list.itemAt(hold.point.pressPosition.x, hold.point.pressPosition.y)
                                if (!slot)
                                    return
                                hold.armed = true
                                hold.pressedKey = ""
                                hold.carried = true
                                view.beginDrag(slot.modelData, slot.cardItem, hold.point.scenePosition)
                            }
                        }

                        // Cards slide to their new places when notes appear, vanish or the order changes.
                        displaced: Transition {
                            enabled: !view.reordering
                            NumberAnimation { properties: "y"; duration: Kirigami.Units.longDuration; easing.type: Easing.OutCubic }
                        }
                        remove: Transition {
                            NumberAnimation { property: "opacity"; to: 0; duration: Kirigami.Units.shortDuration }
                        }

                        // A slot around the card (its height never changes); during a drag the card slides inside it.
                        delegate: Item {
                            id: slot
                            required property int index
                            required property var modelData
                            readonly property bool dragged: dragLayer.active && dragLayer.noteKey === modelData.key
                            readonly property alias cardItem: card
                            // The card slides out of the way of the carried one (see insertIndex).
                            readonly property real shift: {
                                var t = view.insertIndex, c = view.carriedIndex
                                if (t < 0 || c < 0 || dragged)
                                    return 0
                                var d = view.dragHeight + list.spacing
                                if (t < c && index >= t && index < c)
                                    return d
                                if (t > c && index > c && index <= t)
                                    return -d
                                return 0
                            }

                            width: list.width
                            height: card.implicitHeight

                            // The placeholder takes the place of the slot it lands on. A binding, not a one-off
                            // measurement: while the list scrolls the slots are created and laid out later.
                            Binding {
                                target: view
                                property: "placeholderY"
                                when: view.carriedIndex >= 0 && view.insertIndex === slot.index
                                value: slot.index <= view.carriedIndex ? slot.y : slot.y + slot.height - view.dragHeight
                            }

                            NoteCard {
                                id: card
                                y: slot.shift
                                Behavior on y {
                                    enabled: dragLayer.active
                                    NumberAnimation { duration: Kirigami.Units.longDuration; easing.type: Easing.OutCubic }
                                }
                                width: slot.width
                                // Carried: the placeholder stands in; without one (nowhere to drop) it stays dimmed.
                                opacity: slot.dragged ? (view.insertIndex >= 0 ? 0 : 0.35) : 1
                                // Pressed in place: the card sinks a little, a hint that holding picks it up.
                                scale: hold.pressedKey === slot.modelData.key ? 0.97 : 1
                                Behavior on scale {
                                    NumberAnimation { duration: Kirigami.Units.longDuration; easing.type: Easing.OutCubic }
                                }
                                Behavior on opacity {
                                    NumberAnimation { duration: Kirigami.Units.shortDuration }
                                }
                                note: slot.modelData
                                showAccount: view.vm.showAccounts
                                accountIcon: view.vm.accountIcon(slot.modelData.accountKey)
                            }
                        }

                        // Marks where the carried note would land.
                        Rectangle {
                            visible: view.insertIndex >= 0
                            x: 0
                            y: view.placeholderY
                            Behavior on y {
                                enabled: view.placeholderLive
                                NumberAnimation { duration: Kirigami.Units.longDuration; easing.type: Easing.OutCubic }
                            }
                            width: list.width
                            height: view.dragHeight
                            radius: Kirigami.Units.smallSpacing * 2
                            color: Qt.alpha(Kirigami.Theme.highlightColor, 0.12)
                            border.width: 2
                            border.color: Qt.alpha(Kirigami.Theme.highlightColor, 0.6)
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
        }
    }

    // Floats above the layout while a note is dragged; DropAreas in the rail receive its Drag events.
    DragLayer {
        id: dragLayer
        anchors.fill: parent
        z: 100
    }

    // Hidden field used only to reach the clipboard (plain QML has no clipboard API).
    TextEdit { id: clipboard; visible: false }
    function copyToClipboard(text) {
        clipboard.text = text
        clipboard.selectAll()
        clipboard.copy()
        clipboard.text = ""
    }

    PlasmaExtras.Menu {
        id: noteMenu
        property var note: null
        readonly property bool inTrash: note !== null && note.trashed
        readonly property var colors: note !== null && view.vm.capabilities(note.accountKey)
                                      ? view.vm.capabilities(note.accountKey).colors : []

        // The menu is a window of its own (native look, shadow); it opens at the pointer.
        function openFor(n, item, position) {
            note = n
            visualParent = item
            open(Math.round(position.x), Math.round(position.y))
        }

        PlasmaExtras.MenuItem {
            visible: !noteMenu.inTrash
            text: noteMenu.note !== null && noteMenu.note.pinned ? i18n("Unpin") : i18n("Pin")
            icon: "pin"
            onClicked: view.vm.setPinned(noteMenu.note.key, !noteMenu.note.pinned)
        }
        PlasmaExtras.MenuItem {
            visible: !noteMenu.inTrash && noteMenu.colors.length > 0
            text: i18n("Color…")
            icon: "color-management"
            onClicked: colorPopup.openFor(noteMenu.note)
        }
        PlasmaExtras.MenuItem {
            text: i18n("Copy as text")
            icon: "edit-copy"
            onClicked: view.copyToClipboard(view.vm.noteText(noteMenu.note.key))
        }
        PlasmaExtras.MenuItem {
            visible: !noteMenu.inTrash
            text: noteMenu.note !== null && noteMenu.note.archived ? i18n("Unarchive") : i18n("Archive")
            icon: "archive-insert"
            onClicked: view.vm.archiveNote(noteMenu.note.key, !noteMenu.note.archived)
        }
        PlasmaExtras.MenuItem {
            visible: !noteMenu.inTrash
            text: i18n("Move to trash")
            icon: "user-trash"
            onClicked: view.vm.trashNote(noteMenu.note.key)
        }
        PlasmaExtras.MenuItem {
            visible: noteMenu.inTrash
            text: i18n("Restore")
            icon: "edit-undo"
            onClicked: view.vm.restoreNote(noteMenu.note.key)
        }
        PlasmaExtras.MenuItem {
            visible: noteMenu.inTrash
            text: i18n("Delete forever…")
            icon: "edit-delete"
            onClicked: confirmDelete.openFor(noteMenu.note)
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
        // The label gets the dialog's (fixed) width first, so its height can't feed back into the width.
        contentItem: Item {
            implicitHeight: deleteMessage.implicitHeight
            PlasmaComponents.Label {
                id: deleteMessage
                width: parent.width
                wrapMode: Text.Wrap
                text: i18n("This note will be deleted permanently and can't be restored.")
            }
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
        // The label gets the dialog's (fixed) width first, so its height can't feed back into the width.
        contentItem: Item {
            implicitHeight: emptyMessage.implicitHeight
            PlasmaComponents.Label {
                id: emptyMessage
                width: parent.width
                wrapMode: Text.Wrap
                text: i18n("All notes in the trash will be deleted permanently and can't be restored.")
            }
        }
        onAccepted: view.vm.emptyTrash()
    }
}
