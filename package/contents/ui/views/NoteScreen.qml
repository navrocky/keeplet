import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami
import "keepColors.js" as KeepColors

// The open note, full width: title, text or checklist, color, undo/redo. Presentation only; every
// change goes through the NoteEditorViewModel. The group rail is intentionally not shown here.
Rectangle {
    id: screen

    required property var vm       // NotesViewModel
    required property var editor   // NoteEditorViewModel

    // Keep the last note on screen while the screen slides out after the note was closed.
    property var lastNote: null
    readonly property var note: editor.note !== null ? editor.note : lastNote
    Connections {
        target: screen.editor
        function onNoteChanged() {
            if (screen.editor.note !== null)
                screen.lastNote = screen.editor.note
        }
    }
    Component.onCompleted: lastNote = editor.note

    // Palette follows the theme; overridable for previews and tests.
    property bool dark: KeepColors.isDark(Kirigami.Theme.backgroundColor)
    readonly property bool colored: note !== null && KeepColors.has(note.color)
    readonly property color textColor: colored ? KeepColors.textOn(note.color, dark) : Kirigami.Theme.textColor
    readonly property bool isList: note !== null && note.type === "LIST"

    property bool confirmDelete: false

    color: colored ? KeepColors.background(note.color, dark) : Kirigami.Theme.backgroundColor
    Behavior on color { ColorAnimation { duration: Kirigami.Units.longDuration } }

    function showColors() { colorPopup.open() }

    // Ctrl+Z / Ctrl+Shift+Z / Ctrl+Y belong to the note's history, not to a single text field.
    function handleUndoKeys(event) {
        if (!(event.modifiers & Qt.ControlModifier))
            return
        if (event.key === Qt.Key_Z && (event.modifiers & Qt.ShiftModifier) || event.key === Qt.Key_Y) {
            editor.redo()
            event.accepted = true
        } else if (event.key === Qt.Key_Z) {
            editor.undo()
            event.accepted = true
        }
    }

    Shortcut {
        sequences: [StandardKey.Undo]
        enabled: screen.editor.canUndo
        onActivated: screen.editor.undo()
    }
    Shortcut {
        sequences: [StandardKey.Redo]
        enabled: screen.editor.canRedo
        onActivated: screen.editor.redo()
    }

    Timer {
        id: confirmReset
        interval: 4000
        onTriggered: screen.confirmDelete = false
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        RowLayout {
            Layout.fillWidth: true
            spacing: 0

            PlasmaComponents.ToolButton {
                icon.name: "go-previous"
                onClicked: screen.editor.close()
                PlasmaComponents.ToolTip.text: i18n("Back to notes")
                PlasmaComponents.ToolTip.visible: hovered
            }

            QQC2.TextField {
                id: titleField
                Layout.fillWidth: true
                text: screen.note ? screen.note.title : ""
                placeholderText: i18n("Title")
                readOnly: !screen.editor.editable
                font.bold: true
                color: screen.textColor
                background: null
                onTextEdited: screen.editor.setTitle(text)
                Keys.onPressed: event => screen.handleUndoKeys(event)
            }

            PlasmaComponents.ToolButton {
                icon.name: "edit-undo"
                enabled: screen.editor.canUndo
                onClicked: screen.editor.undo()
                PlasmaComponents.ToolTip.text: i18n("Undo")
                PlasmaComponents.ToolTip.visible: hovered
            }

            PlasmaComponents.ToolButton {
                icon.name: "edit-redo"
                enabled: screen.editor.canRedo
                onClicked: screen.editor.redo()
                PlasmaComponents.ToolTip.text: i18n("Redo")
                PlasmaComponents.ToolTip.visible: hovered
            }

            PlasmaComponents.ToolButton {
                id: accountButton
                // Only for a new note that is not stored yet and can go to several accounts.
                visible: screen.editor.accountChoices.length > 1
                icon.name: "user"
                onClicked: { accountMenu.items.active = true; accountMenu.visualParent = accountButton; accountMenu.openRelative() }
                PlasmaComponents.ToolTip.text: i18n("Account")
                PlasmaComponents.ToolTip.visible: hovered

                PlasmaExtras.Menu {
                    id: accountMenu

                    // Filled when the menu is first opened (the menu is a native window, created on demand).
                    property Instantiator items: Instantiator {
                        active: false
                        model: screen.editor.accountChoices
                        delegate: PlasmaExtras.MenuItem {
                            required property var modelData
                            text: modelData.name
                            checkable: true
                            checked: screen.note !== null && screen.note.accountKey === modelData.key
                            onClicked: screen.editor.setAccount(modelData.key)
                        }
                        onObjectAdded: (index, object) => accountMenu.addMenuItem(object)
                        onObjectRemoved: (index, object) => accountMenu.removeMenuItem(object)
                    }
                }
            }

            PlasmaComponents.ToolButton {
                id: labelsButton
                visible: screen.editor.labelChoices.length > 0
                enabled: screen.editor.editable
                icon.name: "tag"
                onClicked: { labelsMenu.items.active = true; labelsMenu.visualParent = labelsButton; labelsMenu.openRelative() }
                PlasmaComponents.ToolTip.text: i18n("Labels")
                PlasmaComponents.ToolTip.visible: hovered

                PlasmaExtras.Menu {
                    id: labelsMenu

                    // Filled when the menu is first opened (the menu is a native window, created on demand).
                    property Instantiator items: Instantiator {
                        active: false
                        model: screen.editor.labelChoices
                        delegate: PlasmaExtras.MenuItem {
                            required property var modelData
                            text: modelData.name
                            checkable: true
                            checked: modelData.on
                            onClicked: screen.editor.toggleLabel(modelData.id)
                        }
                        onObjectAdded: (index, object) => labelsMenu.addMenuItem(object)
                        onObjectRemoved: (index, object) => labelsMenu.removeMenuItem(object)
                    }
                }
            }

            PlasmaComponents.ToolButton {
                id: colorButton
                visible: screen.editor.colors.length > 0
                enabled: screen.editor.editable
                icon.name: "color-management"
                onClicked: colorPopup.opened ? colorPopup.close() : screen.showColors()
                PlasmaComponents.ToolTip.text: i18n("Note color")
                PlasmaComponents.ToolTip.visible: hovered
            }

            PlasmaComponents.ToolButton {
                enabled: screen.editor.editable
                checkable: true
                checked: screen.note !== null && screen.note.pinned
                icon.name: "pin"
                onClicked: screen.editor.togglePinned()
                PlasmaComponents.ToolTip.text: checked ? i18n("Unpin") : i18n("Pin")
                PlasmaComponents.ToolTip.visible: hovered
            }

            PlasmaComponents.ToolButton {
                id: moreButton
                enabled: screen.editor.editable
                icon.name: "overflow-menu"
                onClicked: { moreMenu.visualParent = moreButton; moreMenu.openRelative() }

                PlasmaExtras.Menu {
                    id: moreMenu

                    PlasmaExtras.MenuItem {
                        text: screen.note !== null && screen.note.archived ? i18n("Unarchive") : i18n("Archive")
                        icon: "archive-insert"
                        onClicked: screen.editor.setArchived(!(screen.note !== null && screen.note.archived))
                    }
                    PlasmaExtras.MenuItem {
                        text: screen.isList ? i18n("Convert to text") : i18n("Convert to list")
                        icon: screen.isList ? "text-plain" : "view-list-details"
                        visible: screen.editor.canConvert
                        onClicked: screen.isList ? screen.editor.convertToText() : screen.editor.convertToList()
                    }
                    PlasmaExtras.MenuItem {
                        text: i18n("Clear completed items")
                        icon: "edit-clear-all"
                        visible: screen.editor.hasDone
                        onClicked: list.structural(function () { screen.editor.clearDone() })
                    }
                    PlasmaExtras.MenuItem {
                        text: i18n("Move to trash")
                        icon: "user-trash"
                        onClicked: screen.editor.trash()
                    }
                }
            }
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: screen.editor.trashed
            type: Kirigami.MessageType.Information
            text: i18n("This note is in the trash.")
            actions: [
                Kirigami.Action {
                    text: i18n("Restore")
                    icon.name: "edit-undo"
                    onTriggered: screen.editor.restore()
                },
                Kirigami.Action {
                    text: screen.confirmDelete ? i18n("Click again to delete forever") : i18n("Delete forever")
                    icon.name: "edit-delete"
                    onTriggered: {
                        if (screen.confirmDelete) {
                            screen.editor.deleteForever()
                        } else {
                            screen.confirmDelete = true
                            confirmReset.restart()
                        }
                    }
                }
            ]
        }

        PlasmaComponents.ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ColumnLayout {
                width: screen.width - Kirigami.Units.largeSpacing * 3
                spacing: Kirigami.Units.smallSpacing

                QQC2.TextArea {
                    id: bodyField
                    Layout.fillWidth: true
                    Layout.minimumHeight: Kirigami.Units.gridUnit * 6
                    visible: !screen.isList
                    text: screen.note && !screen.isList ? screen.note.text : ""
                    placeholderText: i18n("Note")
                    readOnly: !screen.editor.editable
                    wrapMode: TextEdit.Wrap
                    color: screen.textColor
                    background: null
                    onTextChanged: {
                        if (screen.note !== null && !screen.isList && text !== screen.note.text)
                            screen.editor.setText(text)
                    }
                    Keys.onPressed: event => screen.handleUndoKeys(event)
                }

                // Checklist: unchecked items on top, then a collapsible "Done" section. Rows are positioned by
                // hand (one delegate per item, y computed from its section and place), so checking an item,
                // dragging it or folding the section is just a change of y/opacity/height and animates.
                // The model is the item *count*: delegates read their item by index, so typing never
                // recreates them and the text field keeps focus.
                Item {
                    id: list
                    Layout.fillWidth: true
                    Layout.preferredHeight: contentHeight
                    visible: screen.isList
                    clip: true

                    readonly property int rowHeight: Math.max(Kirigami.Units.gridUnit * 2, probe.implicitHeight)
                    readonly property int openCount: screen.editor.openIndexes.length
                    readonly property int doneCount: screen.editor.doneIndexes.length
                    readonly property int doneTop: openCount * rowHeight + rowHeight
                    property bool doneExpanded: true
                    // True while the items themselves change (add, remove, move, clear): rows then jump
                    // instead of sliding, because delegates are bound to indexes, not to items.
                    property bool instant: false
                    property real contentHeight: openCount * rowHeight
                                                 + (doneCount > 0 ? rowHeight + (doneExpanded ? doneCount * rowHeight : 0) : 0)
                    Behavior on contentHeight {
                        enabled: !list.instant
                        NumberAnimation { duration: Kirigami.Units.longDuration; easing.type: Easing.InOutQuad }
                    }

                    // Item index -> {done, pos}: its section and place in it.
                    readonly property var places: {
                        var out = []
                        screen.editor.openIndexes.forEach(function (idx, p) { out[idx] = { done: false, pos: p } })
                        screen.editor.doneIndexes.forEach(function (idx, p) { out[idx] = { done: true, pos: p } })
                        return out
                    }

                    // Drag of one row (by its handle) inside its section.
                    property int dragIndex: -1
                    property real dragOffset: 0
                    readonly property var dragPlace: dragIndex >= 0 && places[dragIndex] ? places[dragIndex] : null
                    readonly property int dragTo: {
                        if (dragPlace === null)
                            return -1
                        var count = dragPlace.done ? doneCount : openCount
                        return Math.max(0, Math.min(count - 1, Math.round(dragPlace.pos + dragOffset / rowHeight)))
                    }

                    function sectionTop(done) { return done ? doneTop : 0 }
                    // Place of an item in its section while a drag opens a gap for the carried row.
                    function slotOf(index) {
                        var pl = places[index]
                        if (!pl)
                            return 0
                        var p = pl.pos
                        if (dragPlace !== null && index !== dragIndex && pl.done === dragPlace.done) {
                            if (dragPlace.pos < dragTo && p > dragPlace.pos && p <= dragTo)
                                p--
                            else if (dragTo < dragPlace.pos && p >= dragTo && p < dragPlace.pos)
                                p++
                        }
                        return p
                    }
                    function endDrag() {
                        var pl = dragPlace
                        var to = dragTo
                        if (pl !== null && to !== pl.pos)
                            structural(function () { screen.editor.moveItemInSection(pl.done, pl.pos, to) })
                        dragIndex = -1
                        dragOffset = 0
                    }
                    function structural(change) {
                        instant = true
                        change()
                        instant = false
                    }

                    // Only to measure a row.
                    QQC2.TextField { id: probe; visible: false }

                    Repeater {
                        id: items
                        model: screen.isList ? screen.note.items.length : 0

                        delegate: Item {
                            id: row
                            required property int index
                            readonly property var item: screen.note !== null && screen.note.items[index]
                                                        ? screen.note.items[index] : null
                            readonly property bool done: item !== null && item.checked
                            readonly property bool dragging: list.dragIndex === index
                            readonly property bool hidden: done && !list.doneExpanded

                            function focusField() { field.forceActiveFocus() }

                            width: list.width
                            height: list.rowHeight
                            z: dragging ? 10 : 0
                            y: {
                                var pl = list.places[index]
                                if (!pl)
                                    return 0
                                if (dragging)
                                    return list.sectionTop(pl.done) + pl.pos * list.rowHeight + list.dragOffset
                                return list.sectionTop(pl.done) + list.slotOf(index) * list.rowHeight
                            }
                            Behavior on y {
                                enabled: !list.instant && !row.dragging
                                NumberAnimation { duration: Kirigami.Units.longDuration; easing.type: Easing.InOutQuad }
                            }
                            opacity: hidden ? 0 : 1
                            visible: opacity > 0
                            Behavior on opacity { NumberAnimation { duration: Kirigami.Units.longDuration } }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: (row.item ? row.item.indent : 0) * Kirigami.Units.gridUnit
                                spacing: 0

                                Kirigami.Icon {
                                    id: handle
                                    visible: screen.editor.editable
                                    source: "handle-sort"
                                    opacity: row.dragging ? 1 : 0.5
                                    Layout.preferredWidth: Kirigami.Units.iconSizes.small
                                    Layout.preferredHeight: Kirigami.Units.iconSizes.small
                                    HoverHandler { cursorShape: Qt.OpenHandCursor }
                                    DragHandler {
                                        target: null
                                        xAxis.enabled: false
                                        cursorShape: Qt.ClosedHandCursor
                                        onActiveChanged: {
                                            if (active) {
                                                list.dragOffset = 0
                                                list.dragIndex = row.index
                                            } else {
                                                list.endDrag()
                                            }
                                        }
                                        onActiveTranslationChanged: {
                                            if (active)
                                                list.dragOffset = activeTranslation.y
                                        }
                                    }
                                }

                                QQC2.CheckBox {
                                    checked: row.item !== null && row.item.checked
                                    enabled: screen.editor.editable
                                    onToggled: screen.editor.toggleItem(row.index)
                                }

                                QQC2.TextField {
                                    id: field
                                    Layout.fillWidth: true
                                    text: row.item ? row.item.text : ""
                                    readOnly: !screen.editor.editable
                                    color: screen.textColor
                                    opacity: row.done ? 0.6 : 1
                                    font.strikeout: row.done
                                    background: null
                                    onTextEdited: screen.editor.setItemText(row.index, text)
                                    onAccepted: list.structural(function () { screen.editor.addItem(row.index) })
                                    Keys.onPressed: event => {
                                        screen.handleUndoKeys(event)
                                        if (event.accepted)
                                            return
                                        if (event.key === Qt.Key_Tab) {
                                            screen.editor.setItemIndent(row.index, 1)
                                            event.accepted = true
                                        } else if (event.key === Qt.Key_Backtab) {
                                            screen.editor.setItemIndent(row.index, 0)
                                            event.accepted = true
                                        } else if (event.key === Qt.Key_Backspace && text === "") {
                                            list.structural(function () { screen.editor.removeItem(row.index) })
                                            event.accepted = true
                                        }
                                    }
                                }

                                PlasmaComponents.ToolButton {
                                    visible: screen.editor.editable
                                    icon.name: "edit-delete"
                                    onClicked: list.structural(function () { screen.editor.removeItem(row.index) })
                                    PlasmaComponents.ToolTip.text: i18n("Remove item")
                                    PlasmaComponents.ToolTip.visible: hovered
                                }
                            }
                        }
                    }

                    // Header of the Done section.
                    Item {
                        id: doneHeader
                        y: list.openCount * list.rowHeight
                        width: list.width
                        height: list.rowHeight
                        visible: list.doneCount > 0

                        RowLayout {
                            anchors.fill: parent
                            spacing: Kirigami.Units.smallSpacing

                            PlasmaComponents.ToolButton {
                                Layout.fillWidth: true
                                // Left-aligned label with the arrow.
                                contentItem: RowLayout {
                                    spacing: Kirigami.Units.smallSpacing
                                    Kirigami.Icon {
                                        source: "arrow-right"
                                        rotation: list.doneExpanded ? 90 : 0
                                        Behavior on rotation { NumberAnimation { duration: Kirigami.Units.longDuration } }
                                        Layout.preferredWidth: Kirigami.Units.iconSizes.small
                                        Layout.preferredHeight: Kirigami.Units.iconSizes.small
                                    }
                                    PlasmaComponents.Label {
                                        Layout.fillWidth: true
                                        text: i18n("Done (%1)", list.doneCount)
                                        color: screen.textColor
                                        elide: Text.ElideRight
                                    }
                                }
                                onClicked: list.doneExpanded = !list.doneExpanded
                            }

                            PlasmaComponents.ToolButton {
                                visible: screen.editor.editable
                                icon.name: "edit-clear-all"
                                onClicked: list.structural(function () { screen.editor.clearDone() })
                                PlasmaComponents.ToolTip.text: i18n("Clear completed items")
                                PlasmaComponents.ToolTip.visible: hovered
                            }
                        }
                    }
                }

                PlasmaComponents.Button {
                    visible: screen.isList && screen.editor.editable
                    icon.name: "list-add"
                    text: i18n("Add item")
                    flat: true
                    onClicked: {
                        var open = screen.editor.openIndexes
                        list.structural(function () {
                            screen.editor.addItem(open.length > 0 ? open[open.length - 1] : -1)
                        })
                    }
                }

                Flow {
                    Layout.fillWidth: true
                    visible: screen.note !== null && screen.note.labels.length > 0
                    spacing: Kirigami.Units.smallSpacing

                    Repeater {
                        model: screen.note ? screen.note.labels : []

                        Rectangle {
                            required property var modelData
                            implicitWidth: chip.implicitWidth + Kirigami.Units.smallSpacing * 2
                            implicitHeight: chip.implicitHeight + 2
                            radius: height / 2
                            color: Qt.alpha(screen.textColor, 0.12)

                            PlasmaComponents.Label {
                                id: chip
                                anchors.centerIn: parent
                                text: parent.modelData.name
                                color: screen.textColor
                                font: Kirigami.Theme.smallFont
                            }
                        }
                    }
                }
            }
        }
    }

    Connections {
        target: screen.editor
        function onItemFocusRequested(index) {
            Qt.callLater(function () {
                var row = items.itemAt(index)
                if (row)
                    row.focusField()
            })
        }
    }

    QQC2.Popup {
        id: colorPopup
        parent: colorButton
        y: colorButton.height
        x: colorButton.width - width
        padding: Kirigami.Units.largeSpacing
        closePolicy: QQC2.Popup.CloseOnEscape | QQC2.Popup.CloseOnPressOutside

        contentItem: ColorPicker {
            colors: screen.editor.colors
            current: screen.note ? screen.note.color : "DEFAULT"
            dark: screen.dark
            onPicked: name => {
                screen.editor.setColor(name)
                colorPopup.close()
            }
        }
    }
}
