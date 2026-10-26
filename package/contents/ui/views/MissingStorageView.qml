import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

// Shown instead of everything else when the QtQuick.LocalStorage module is missing (LocalDb.available is false):
// accounts and notes cannot be stored. Debian, Ubuntu and Kubuntu ship that module as a separate package.
Item {
    id: view

    readonly property string command: "sudo apt install qml6-module-qtquick-localstorage"

    implicitHeight: message.implicitHeight

    Kirigami.PlaceholderMessage {
        id: message
        anchors.centerIn: parent
        width: parent.width - Kirigami.Units.gridUnit * 2
        icon.name: "dialog-warning"
        text: i18n("Keeplet needs the Qt module QtQuick.LocalStorage")
        explanation: i18n("It is where accounts and notes are stored. On Kubuntu, Ubuntu and Debian install it with:<br><br><tt>%1</tt><br><br>On openSUSE the package is qt6-declarative-imports. Then log out and back in.",
                          view.command)
        helpfulAction: QQC2.Action {
            icon.name: "edit-copy"
            text: i18n("Copy command")
            onTriggered: {
                clipboard.text = view.command
                clipboard.selectAll()
                clipboard.copy()
                clipboard.text = ""
            }
        }
    }

    // Hidden field used only to reach the clipboard (plain QML has no clipboard API).
    TextEdit { id: clipboard; visible: false }
}
