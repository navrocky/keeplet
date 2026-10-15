import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import "viewmodel"
import "views"
import "services"

PlasmoidItem {
    id: root

    Plasmoid.icon: "knotes"
    toolTipSubText: accountsVm.signedIn
                    ? accountsVm.accounts.map(function (a) { return a.displayName }).join(", ")
                    : i18n("Not signed in")

    // Services: global (shared by every instance of the widget).
    LocalDb { id: localDb }
    AccountsService { id: accountsService; db: localDb }
    NotesCache { id: notesCache; db: localDb }

    // ViewModels.
    AccountsViewModel {
        id: accountsVm
        service: accountsService
        configuration: Plasmoid.configuration
    }

    NotesViewModel {
        id: notesVm
        accounts: accountsVm
        cache: notesCache
        syncInterval: Plasmoid.configuration.syncInterval
    }

    // Accounts created by the single-account layout of earlier versions.
    Component.onCompleted: {
        accountsService.migrateLegacy(Plasmoid.configuration).then(function (migrated) {
            if (migrated)
                accountsVm.reload()
        }).catch(function (e) {
            console.warn("Keeplet: account migration failed:", e)
        })
    }

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18n("Add Account…")
            icon.name: "list-add"
            visible: accountsVm.signedIn
            onTriggered: accountsVm.requestSignIn()
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
            sourceComponent: accountsVm.signedIn && !accountsVm.signInRequested ? notesView : signInView
        }

        Component {
            id: signInView
            SignInView { accounts: accountsVm }
        }

        Component {
            id: notesView
            NotesView { vm: notesVm; accountsVm: accountsVm }
        }
    }
}
