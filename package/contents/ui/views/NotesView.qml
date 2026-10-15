import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

// Notes screen. Presentation only: reads and commands go through the ViewModel.
ColumnLayout {
    id: view

    required property var vm

    spacing: Kirigami.Units.smallSpacing

    function errorText(code, detail) {
        switch (code) {
        case "network": return i18n("Can't reach Google Keep. Showing saved notes.")
        case "unauthorized": return i18n("Google Keep refused the session. Try again in a moment.")
        case "failed": return i18n("Sync failed: %1", detail)
        default: return ""
        }
    }

    RowLayout {
        Layout.fillWidth: true

        PlasmaComponents.TextField {
            Layout.fillWidth: true
            placeholderText: i18n("Search notes")
            onTextChanged: view.vm.searchText = text
        }

        PlasmaComponents.ToolButton {
            icon.name: "view-refresh"
            enabled: !view.vm.syncing
            onClicked: view.vm.refresh()
            PlasmaComponents.ToolTip.text: i18n("Sync now")
            PlasmaComponents.ToolTip.visible: hovered
        }
    }

    PlasmaComponents.ProgressBar {
        Layout.fillWidth: true
        indeterminate: true
        visible: view.vm.syncing
    }

    Kirigami.InlineMessage {
        Layout.fillWidth: true
        type: Kirigami.MessageType.Warning
        text: view.errorText(view.vm.error, view.vm.errorDetail)
        visible: text !== ""
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
                required property var modelData
                width: list.width
                note: modelData
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
