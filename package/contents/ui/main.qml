import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    Plasmoid.icon: "knotes"
    toolTipSubText: account.signedIn ? account.email : i18n("Not signed in")

    Auth {
        id: account
        configuration: Plasmoid.configuration
    }

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18n("Sign Out")
            icon.name: "system-log-out"
            visible: account.signedIn
            onTriggered: account.signOut()
        }
    ]

    fullRepresentation: Item {
        Layout.preferredWidth: Kirigami.Units.gridUnit * 22
        Layout.preferredHeight: Kirigami.Units.gridUnit * 26
        Layout.minimumWidth: Kirigami.Units.gridUnit * 16
        Layout.minimumHeight: Kirigami.Units.gridUnit * 16

        Loader {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.smallSpacing
            sourceComponent: account.signedIn ? signedInView : signInView
        }

        Component {
            id: signInView
            SignInView { auth: account }
        }

        // Placeholder until notes are implemented (stage 2).
        Component {
            id: signedInView
            ColumnLayout {
                PlasmaComponents.Label {
                    Layout.alignment: Qt.AlignCenter
                    text: i18n("Signed in as %1", account.email)
                }
                PlasmaComponents.Label {
                    Layout.alignment: Qt.AlignCenter
                    opacity: 0.7
                    text: account.storage === "config"
                          ? i18n("KWallet is disabled: the key is stored in the widget settings.")
                          : i18n("The key is stored in KWallet.")
                }
                PlasmaComponents.Button {
                    Layout.alignment: Qt.AlignCenter
                    text: i18n("Sign Out")
                    icon.name: "system-log-out"
                    onClicked: account.signOut()
                }
            }
        }
    }
}
