import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
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
        railCollapsed: Plasmoid.configuration.railCollapsed
        // The View toggles the property directly; persist it per widget instance.
        onRailCollapsedChanged: Plasmoid.configuration.railCollapsed = railCollapsed
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
        Layout.preferredWidth: Kirigami.Units.gridUnit * 30
        Layout.preferredHeight: Kirigami.Units.gridUnit * 28
        Layout.minimumWidth: Kirigami.Units.gridUnit * 18
        Layout.minimumHeight: Kirigami.Units.gridUnit * 16

        // loading -> sign-in form or notes, cross-faded.
        readonly property string target: !accountsVm.ready ? "loading"
                                         : (accountsVm.signedIn && !accountsVm.signInRequested ? "notes" : "signin")

        QQC2.StackView {
            id: stack
            anchors.fill: parent
            anchors.margins: Kirigami.Units.smallSpacing
            initialItem: loadingScreen

            replaceEnter: Transition {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Kirigami.Units.longDuration }
            }
            replaceExit: Transition {
                NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Kirigami.Units.longDuration }
            }
        }

        onTargetChanged: {
            var c = target === "notes" ? notesRoot : (target === "signin" ? signInView : loadingScreen)
            stack.replace(null, c)
        }

        Component {
            id: loadingScreen
            Item {}
        }

        Component {
            id: signInView
            SignInView { accounts: accountsVm }
        }

        Component {
            id: notesRoot
            NotesRoot { vm: notesVm; accountsVm: accountsVm }
        }
    }
}
