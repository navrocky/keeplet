import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.components as PlasmaComponents
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
                onClicked: accountMenu.popup(accountButton, 0, accountButton.height)
                PlasmaComponents.ToolTip.text: i18n("Account")
                PlasmaComponents.ToolTip.visible: hovered

                QQC2.Menu {
                    id: accountMenu

                    Instantiator {
                        model: screen.editor.accountChoices
                        delegate: QQC2.MenuItem {
                            required property var modelData
                            text: modelData.name
                            checkable: true
                            checked: screen.note !== null && screen.note.accountKey === modelData.key
                            onTriggered: screen.editor.setAccount(modelData.key)
                        }
                        onObjectAdded: (index, object) => accountMenu.addItem(object)
                        onObjectRemoved: (index, object) => accountMenu.removeItem(object)
                    }
                }
            }

            PlasmaComponents.ToolButton {
                id: labelsButton
                visible: screen.editor.labelChoices.length > 0
                enabled: screen.editor.editable
                icon.name: "tag"
                onClicked: labelsMenu.popup(labelsButton, 0, labelsButton.height)
                PlasmaComponents.ToolTip.text: i18n("Labels")
                PlasmaComponents.ToolTip.visible: hovered

                QQC2.Menu {
                    id: labelsMenu

                    Instantiator {
                        model: screen.editor.labelChoices
                        delegate: QQC2.MenuItem {
                            required property var modelData
                            text: modelData.name
                            checkable: true
                            checked: modelData.on
                            onTriggered: screen.editor.toggleLabel(modelData.id)
                        }
                        onObjectAdded: (index, object) => labelsMenu.addItem(object)
                        onObjectRemoved: (index, object) => labelsMenu.removeItem(object)
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
                onClicked: moreMenu.popup(moreButton, 0, moreButton.height)

                QQC2.Menu {
                    id: moreMenu

                    QQC2.MenuItem {
                        text: screen.note !== null && screen.note.archived ? i18n("Unarchive") : i18n("Archive")
                        icon.name: "archive-insert"
                        onTriggered: screen.editor.setArchived(!(screen.note !== null && screen.note.archived))
                    }
                    QQC2.MenuItem {
                        text: i18n("Move to trash")
                        icon.name: "user-trash"
                        onTriggered: screen.editor.trash()
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

                // The model is the item *count*: delegates read their item by index, so typing never
                // recreates them and the text field keeps focus.
                Repeater {
                    id: items
                    model: screen.isList ? screen.note.items.length : 0

                    delegate: RowLayout {
                        id: row
                        required property int index
                        readonly property var item: screen.note !== null && screen.note.items[index]
                                                    ? screen.note.items[index] : null

                        Layout.fillWidth: true
                        Layout.leftMargin: (item ? item.indent : 0) * Kirigami.Units.gridUnit

                        function focusField() { field.forceActiveFocus() }

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
                            opacity: row.item !== null && row.item.checked ? 0.6 : 1
                            font.strikeout: row.item !== null && row.item.checked
                            background: null
                            onTextEdited: screen.editor.setItemText(row.index, text)
                            onAccepted: screen.editor.addItem(row.index)
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
                                    screen.editor.removeItem(row.index)
                                    event.accepted = true
                                }
                            }
                        }

                        PlasmaComponents.ToolButton {
                            visible: screen.editor.editable
                            icon.name: "edit-delete"
                            onClicked: screen.editor.removeItem(row.index)
                            PlasmaComponents.ToolTip.text: i18n("Remove item")
                            PlasmaComponents.ToolTip.visible: hovered
                        }
                    }
                }

                PlasmaComponents.Button {
                    visible: screen.isList && screen.editor.editable
                    icon.name: "list-add"
                    text: i18n("Add item")
                    flat: true
                    onClicked: screen.editor.addItem(screen.note.items.length - 1)
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
