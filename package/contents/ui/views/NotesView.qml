import QtQuick
import QtQuick.Layouts
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
