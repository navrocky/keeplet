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

    // The note is a rounded, colored panel (like its card in the list) inside the widget's own background.
    color: "transparent"
    readonly property color panelColor: colored ? KeepColors.background(note.color, dark) : Kirigami.Theme.backgroundColor

    Rectangle {
        id: panel
        anchors.fill: parent
        radius: Kirigami.Units.smallSpacing * 2
        color: screen.panelColor
        border.width: 1
        border.color: screen.colored ? (screen.dark ? Qt.lighter(color, 1.4) : Qt.darker(color, 1.15))
                                     : Qt.alpha(Kirigami.Theme.textColor, 0.2)
        Behavior on color { ColorAnimation { duration: Kirigami.Units.longDuration } }
    }

    // Hidden field used only to reach the clipboard (plain QML has no clipboard API).
    TextEdit { id: clipboard; visible: false }
    function copyText() {
        clipboard.text = editor.asText()
        clipboard.selectAll()
        clipboard.copy()
        clipboard.text = ""
    }

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
                        text: i18n("Copy as text")
                        icon: "edit-copy"
                        onClicked: screen.copyText()
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

                    // Rows are as tall as their text (items may wrap to several lines) but never below rowHeight.
                    readonly property int rowHeight: Math.max(Kirigami.Units.gridUnit * 2, probe.implicitHeight)
                    readonly property int openCount: screen.editor.openIndexes.length
                    readonly property int doneCount: screen.editor.doneIndexes.length
                    // Item uid -> its row's height; delegates report it.
                    property var rowHeights: ({})
                    function heightOf(index) {
                        var it = screen.note !== null ? screen.note.items[index] : null
                        return (it && rowHeights[it.uid]) || rowHeight
                    }
                    function setHeight(uid, h) {
                        if (rowHeights[uid] === h)
                            return
                        var copy = Object.assign({}, rowHeights)
                        copy[uid] = h
                        rowHeights = copy
                    }
                    function indexOfUid(uid) { return screen.editor.itemIndexOf(uid) }

                    // One row per item, kept in step with the editor's items: rows are inserted, removed and moved,
                    // never rebound to another item, so an insert costs one new row and the others just slide.
                    ListModel { id: rows }
                    function syncRows() {
                        var want = screen.editor.itemUids
                        var wanted = {}
                        want.forEach(function (u) { wanted[u] = true })
                        for (var i = rows.count - 1; i >= 0; i--) {
                            if (!wanted[rows.get(i).uid])
                                rows.remove(i)
                        }
                        for (var k = 0; k < want.length; k++) {
                            if (k < rows.count && rows.get(k).uid === want[k])
                                continue
                            var from = -1
                            for (var m = k + 1; m < rows.count; m++) {
                                if (rows.get(m).uid === want[k]) {
                                    from = m
                                    break
                                }
                            }
                            if (from >= 0)
                                rows.move(from, k, 1)
                            else
                                rows.insert(k, { uid: want[k] })
                        }
                    }
                    Connections {
                        target: screen.editor
                        function onItemUidsChanged() { list.syncRows() }
                    }
                    Component.onCompleted: syncRows()
                    Connections {
                        target: screen.editor
                        function onNoteKeyChanged() { list.doneExpanded = false }
                    }

                    function sumHeights(indexes) {
                        var total = 0
                        indexes.forEach(function (i) { total += heightOf(i) })
                        return total
                    }
                    readonly property real openHeight: sumHeights(screen.editor.openIndexes)
                    readonly property real doneHeight: sumHeights(screen.editor.doneIndexes)
                    readonly property real doneTop: openHeight + rowHeight
                    // Finished items start folded, for every note that is opened.
                    property bool doneExpanded: false
                    property real contentHeight: openHeight + (doneCount > 0 ? rowHeight + (doneExpanded ? doneHeight : 0) : 0)
                    Behavior on contentHeight {
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
                    // Top of the carried row inside its section before the drag moved anything.
                    readonly property real dragNaturalTop: {
                        if (dragPlace === null)
                            return 0
                        var order = dragPlace.done ? screen.editor.doneIndexes : screen.editor.openIndexes
                        return sumHeights(order.slice(0, dragPlace.pos))
                    }
                    // Place the carried row would take: how many of the other rows lie above its center.
                    readonly property int dragTo: {
                        if (dragPlace === null)
                            return -1
                        var order = dragPlace.done ? screen.editor.doneIndexes : screen.editor.openIndexes
                        var center = dragNaturalTop + heightOf(dragIndex) / 2 + dragOffset
                        var y = 0
                        var n = 0
                        order.forEach(function (i) {
                            if (i === dragIndex)
                                return
                            if (y + heightOf(i) / 2 < center)
                                n++
                            y += heightOf(i)
                        })
                        return n
                    }

                    // Item index -> y of its row: sections stacked, rows by height; while dragging the carried row
                    // sits at its new place so the others open a gap for it.
                    readonly property var tops: {
                        var out = []
                        ;[false, true].forEach(function (done) {
                            var order = (done ? screen.editor.doneIndexes : screen.editor.openIndexes).slice()
                            if (dragPlace !== null && dragPlace.done === done) {
                                order.splice(order.indexOf(dragIndex), 1)
                                order.splice(dragTo, 0, dragIndex)
                            }
                            var y = done ? doneTop : 0
                            order.forEach(function (i) {
                                out[i] = y
                                y += heightOf(i)
                            })
                        })
                        return out
                    }

                    // Visual order of the rows: open items, then done ones.
                    function visualOrder() {
                        return screen.editor.openIndexes.concat(screen.editor.doneIndexes)
                    }
                    // Item index next to `index` in visual order (dir -1 / +1), -1 at the ends.
                    function neighbor(index, dir) {
                        var order = visualOrder()
                        var at = order.indexOf(index) + dir
                        return at >= 0 && at < order.length ? order[at] : -1
                    }
                    function focusItem(index, x, edge) {
                        var target = items.itemAt(index)
                        // The cursor going down into a folded Done section unfolds it.
                        if (target && target.done && !doneExpanded)
                            doneExpanded = true
                        if (target)
                            target.focusField(x, edge)
                    }

                    function sectionTopOf(done) { return done ? doneTop : 0 }
                    function sectionHeightOf(done) { return done ? doneHeight : openHeight }

                    function endDrag() {
                        var pl = dragPlace
                        var to = dragTo
                        if (pl !== null && to !== pl.pos)
                            structural(function () { screen.editor.moveItemInSection(pl.done, pl.pos, to) })
                        dragIndex = -1
                        dragOffset = 0
                    }
                    // (Kept as a seam for commands that rearrange items.)
                    function structural(change) { change() }

                    // Only to measure a one-line row.
                    QQC2.TextArea { id: probe; visible: false }

                    Repeater {
                        id: items
                        model: rows

                        delegate: Item {
                            id: row
                            required property string uid
                            // The item's place in the note; rows follow their item when it moves.
                            readonly property int index: list.indexOfUid(uid)
                            readonly property var item: screen.note !== null && index >= 0 ? screen.note.items[index] : null
                            readonly property bool done: item !== null && item.checked
                            readonly property bool dragging: list.dragIndex === index
                            readonly property bool hidden: done && !list.doneExpanded

                            // Focus the field; `x` / `edge` ("first" or "last" line) put the cursor under that column,
                            // without them the cursor goes to the end of the text.
                            function focusField(x, edge) {
                                field.forceActiveFocus()
                                if (edge === undefined) {
                                    field.cursorPosition = field.length
                                } else {
                                    var y = edge === "first" ? field.positionToRectangle(0).y + 1
                                                             : field.positionToRectangle(field.length).y + 1
                                    field.cursorPosition = field.positionAt(x, y)
                                }
                            }

                            width: list.width
                            height: Math.max(list.rowHeight, line.implicitHeight)
                            onHeightChanged: list.setHeight(uid, height)
                            Component.onCompleted: list.setHeight(uid, height)
                            z: dragging ? 10 : 0
                            y: {
                                var pl = list.places[index]
                                if (!pl)
                                    return 0
                                if (dragging) {
                                    var top = list.sectionTopOf(pl.done)
                                    return Math.max(top, Math.min(top + list.sectionHeightOf(pl.done) - height,
                                                                  top + list.dragNaturalTop + list.dragOffset))
                                }
                                return list.tops[index] === undefined ? 0 : list.tops[index]
                            }
                            Behavior on y {
                                enabled: !row.dragging
                                NumberAnimation { duration: Kirigami.Units.longDuration; easing.type: Easing.InOutQuad }
                            }
                            opacity: hidden ? 0 : 1
                            visible: opacity > 0 || !hidden
                            Behavior on opacity {
                                NumberAnimation { duration: Kirigami.Units.longDuration }
                            }

                            RowLayout {
                                id: line
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: (row.item ? row.item.indent : 0) * Kirigami.Units.gridUnit
                                spacing: 0

                                // Controls keep the height of a one-line row and stay at the first line.
                                Item {
                                    visible: screen.editor.editable
                                    Layout.alignment: Qt.AlignTop
                                    Layout.preferredWidth: Kirigami.Units.iconSizes.small
                                    Layout.preferredHeight: list.rowHeight

                                    Kirigami.Icon {
                                        id: handle
                                        anchors.centerIn: parent
                                        width: Kirigami.Units.iconSizes.small
                                        height: width
                                        source: "handle-sort"
                                        opacity: row.dragging ? 1 : 0.5
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
                                }

                                Item {
                                    Layout.alignment: Qt.AlignTop
                                    Layout.preferredWidth: box.implicitWidth
                                    Layout.preferredHeight: list.rowHeight

                                    QQC2.CheckBox {
                                        id: box
                                        anchors.centerIn: parent
                                        checked: row.item !== null && row.item.checked
                                        enabled: screen.editor.editable
                                        onToggled: screen.editor.toggleItem(row.index)
                                    }
                                }

                                QQC2.TextArea {
                                    id: field
                                    Layout.fillWidth: true
                                    Layout.minimumHeight: list.rowHeight
                                    verticalAlignment: TextEdit.AlignVCenter
                                    wrapMode: TextEdit.Wrap
                                    text: row.item ? row.item.text : ""
                                    readOnly: !screen.editor.editable
                                    color: screen.textColor
                                    opacity: row.done ? 0.6 : 1
                                    font.strikeout: row.done
                                    background: null
                                    onTextChanged: {
                                        if (row.item !== null && text !== row.item.text)
                                            screen.editor.setItemText(row.index, text)
                                    }
                                    Keys.onPressed: event => {
                                        screen.handleUndoKeys(event)
                                        if (event.accepted)
                                            return
                                        var plain = !(event.modifiers & (Qt.ShiftModifier | Qt.ControlModifier | Qt.AltModifier))
                                        var enter = event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                                        var oneCursor = selectionStart === selectionEnd
                                        if (enter && (event.modifiers & Qt.ShiftModifier)) {
                                            // Shift+Enter always breaks the line.
                                            insert(cursorPosition, "\n")
                                            event.accepted = true
                                        } else if (enter && plain && oneCursor && length > 0 && cursorPosition === 0) {
                                            // At the start: a new item above takes the cursor.
                                            list.structural(function () { screen.editor.addItemAbove(row.index) })
                                            event.accepted = true
                                        } else if (enter && plain && oneCursor && cursorPosition === length) {
                                            // At the end (or in an empty item): a new item below.
                                            list.structural(function () { screen.editor.addItem(row.index) })
                                            event.accepted = true
                                        } else if ((event.key === Qt.Key_Up || event.key === Qt.Key_Down) && plain) {
                                            // On the first / last line the arrows move to the neighbouring item.
                                            var up = event.key === Qt.Key_Up
                                            var edgeY = up ? positionToRectangle(0).y : positionToRectangle(length).y
                                            var onEdge = Math.abs(cursorRectangle.y - edgeY) < cursorRectangle.height / 2
                                            if (onEdge) {
                                                var other = list.neighbor(row.index, up ? -1 : 1)
                                                if (other >= 0)
                                                    list.focusItem(other, cursorRectangle.x, up ? "last" : "first")
                                                event.accepted = true
                                            }
                                        } else if (event.key === Qt.Key_Tab) {
                                            screen.editor.setItemIndent(row.index, 1)
                                            event.accepted = true
                                        } else if (event.key === Qt.Key_Backtab) {
                                            screen.editor.setItemIndent(row.index, 0)
                                            event.accepted = true
                                        } else if (event.key === Qt.Key_Backspace && text === "") {
                                            // Remove the empty item; the cursor goes to the end of the previous one.
                                            var host = list
                                            var prev = host.neighbor(row.index, -1)
                                            var next = host.neighbor(row.index, 1)
                                            var self = row.index
                                            host.structural(function () { screen.editor.removeItem(self) })
                                            // (This delegate may be gone by now: only `host` is used afterwards.)
                                            if (prev >= 0) {
                                                Qt.callLater(function () { host.focusItem(prev > self ? prev - 1 : prev) })
                                            } else if (next >= 0) {
                                                // First item: the cursor goes to the start of the next one.
                                                Qt.callLater(function () { host.focusItem(next > self ? next - 1 : next, 0, "first") })
                                            }
                                            event.accepted = true
                                        }
                                    }
                                }

                                Item {
                                    visible: screen.editor.editable
                                    Layout.alignment: Qt.AlignTop
                                    Layout.preferredWidth: remove.implicitWidth
                                    Layout.preferredHeight: list.rowHeight

                                    PlasmaComponents.ToolButton {
                                        id: remove
                                        anchors.centerIn: parent
                                        icon.name: "edit-delete"
                                        onClicked: list.structural(function () { screen.editor.removeItem(row.index) })
                                        PlasmaComponents.ToolTip.text: i18n("Remove item")
                                        PlasmaComponents.ToolTip.visible: hovered
                                    }
                                }
                            }
                        }
                    }

                    // Header of the Done section.
                    Item {
                        id: doneHeader
                        y: list.openHeight
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
