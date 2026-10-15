import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami
import "keepColors.js" as KeepColors

// One note, full width. Read-only for now; the group rail is intentionally not shown here.
Rectangle {
    id: screen

    required property var vm   // NotesViewModel

    // Keep the last note while the screen slides out after the note was closed or removed.
    property var note: null
    Connections {
        target: screen.vm
        function onCurrentNoteChanged() {
            if (screen.vm.currentNote)
                screen.note = screen.vm.currentNote
        }
    }
    Component.onCompleted: note = vm.currentNote

    readonly property bool colored: note !== null && KeepColors.has(note.color)
    readonly property color textColor: colored ? KeepColors.TEXT_ON_COLOR : Kirigami.Theme.textColor

    color: colored ? KeepColors.background(note.color) : Kirigami.Theme.backgroundColor
    Behavior on color { ColorAnimation { duration: Kirigami.Units.longDuration } }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        RowLayout {
            Layout.fillWidth: true

            PlasmaComponents.ToolButton {
                icon.name: "go-previous"
                onClicked: screen.vm.closeNote()
                PlasmaComponents.ToolTip.text: i18n("Back to notes")
                PlasmaComponents.ToolTip.visible: hovered
            }

            PlasmaComponents.Label {
                Layout.fillWidth: true
                text: screen.note ? screen.note.title : ""
                color: screen.textColor
                font.bold: true
                font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.2
                elide: Text.ElideRight
                wrapMode: Text.NoWrap
            }

            Kirigami.Icon {
                visible: screen.note !== null && screen.note.pinned
                source: "pin"
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Kirigami.Units.iconSizes.small
            }
        }

        PlasmaComponents.ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ColumnLayout {
                width: screen.width - Kirigami.Units.largeSpacing * 3
                spacing: Kirigami.Units.smallSpacing

                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    visible: screen.note !== null && screen.note.type === "NOTE"
                    text: screen.note ? screen.note.text : ""
                    color: screen.textColor
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                }

                Repeater {
                    model: screen.note && screen.note.type === "LIST" ? screen.note.items : []

                    PlasmaComponents.Label {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.leftMargin: modelData.indent * Kirigami.Units.gridUnit
                        text: (modelData.checked ? "☑ " : "☐ ") + modelData.text
                        color: screen.textColor
                        opacity: modelData.checked ? 0.6 : 1
                        font.strikeout: modelData.checked
                        wrapMode: Text.Wrap
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
}
