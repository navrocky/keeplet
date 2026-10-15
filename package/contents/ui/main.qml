import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami
import "viewmodel"
import "views"
import "services"

PlasmoidItem {
    id: root

    Plasmoid.icon: "knotes"
    toolTipSubText: account.signedIn ? account.email : i18n("Not signed in")

    AuthViewModel {
        id: account
        configuration: Plasmoid.configuration
    }

    NotesCache { id: notesCache }

    NotesViewModel {
        id: notesVm
        auth: account
        cache: notesCache
        syncInterval: Plasmoid.configuration.syncInterval
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
            sourceComponent: account.signedIn ? notesView : signInView
        }

        Component {
            id: signInView
            SignInView { auth: account }
        }

        Component {
            id: notesView
            NotesView { vm: notesVm }
        }
    }
}
