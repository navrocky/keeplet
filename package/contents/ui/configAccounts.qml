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

    AccountsSettings {
        width: parent ? parent.width : implicitWidth
        accounts: accountsVm
        onAccountsModified: {
            localDb.drain()   // the widgets read the database as soon as they hear about the change
            Plasmoid.configuration.accountsRevision = Plasmoid.configuration.accountsRevision + 1
        }
    }
}
