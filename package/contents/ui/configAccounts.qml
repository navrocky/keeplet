import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.plasma.plasmoid
import "viewmodel"
import "views"
import "services"

// Accounts are global (shared by every widget), so this page works on the shared database directly and is
// deliberately free of cfg_* properties (see configGeneral.qml). The widgets are told about a change through
// the accountsRevision counter.
KCM.SimpleKCM {
    LocalDb { id: localDb }
    AccountsService { id: accountsService; db: localDb }
    AccountsViewModel {
        id: accountsVm
        service: accountsService
    }

    // A centered column of a readable width, like the "About" page, instead of stretching over the dialog.
    Item {
        implicitHeight: settings.implicitHeight + Kirigami.Units.largeSpacing * 2

        AccountsSettings {
            id: settings
            y: Kirigami.Units.largeSpacing
            width: Math.min(parent.width - Kirigami.Units.gridUnit * 2, Kirigami.Units.gridUnit * 30)
            anchors.horizontalCenter: parent.horizontalCenter
            accounts: accountsVm
            onAccountsModified: {
                localDb.drain()   // the widgets read the database as soon as they hear about the change
                Plasmoid.configuration.accountsRevision = Plasmoid.configuration.accountsRevision + 1
            }
        }
    }
}
