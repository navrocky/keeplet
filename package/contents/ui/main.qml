import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami
import "viewmodel"
import "views"
import "services"

PlasmoidItem {
    id: root

    // The packaged icon (art/ has the sources). metadata.json names the same file as "/icons/keeplet.svg" (relative to
    // contents/, understood by the widget explorer), but the applet keeps that string as is, so set a real URL here.
    Plasmoid.icon: Qt.resolvedUrl("../icons/keeplet.svg")
    toolTipSubText: accountsVm.signedIn
                    ? accountsVm.accounts.map(function (a) { return a.displayName }).join(", ")
                    : i18n("Not signed in")

    // Services: global (shared by every instance of the widget).
    LocalDb { id: localDb }
    AccountsService { id: accountsService; db: localDb }
    NotesCache { id: notesCache; db: localDb }
    BrowserSignIn { id: browserSignIn }
    Analytics { id: analytics; db: localDb }
    UpdateCheck { id: updateCheck; db: localDb; enabled: Plasmoid.configuration.checkUpdates }

    // ViewModels.
    AccountsViewModel {
        id: accountsVm
        service: accountsService
        browser: browserSignIn
        analytics: analytics
        configuration: Plasmoid.configuration
    }

    AnalyticsViewModel {
        id: analyticsVm
        service: analytics
    }

    UpdateViewModel {
        id: updateVm
        service: updateCheck
        currentVersion: Plasmoid.metaData.version
    }

    // For the screens created from Components (see notesRoot below).
    readonly property var accountsModel: accountsVm
    readonly property var analyticsModel: analyticsVm
    readonly property var updateModel: updateVm

    // Daily "app_start" (sent at most once a day by all instances together, only with consent).
    readonly property bool heartbeatDue: accountsVm.ready && analytics.enabled
    onHeartbeatDueChanged: {
        if (!heartbeatDue)
            return
        var providers = {}
        accountsVm.accounts.forEach(function (a) { providers[a.providerId] = true })
        analytics.heartbeat({
            widget_version: Plasmoid.metaData.version,
            locale: Qt.locale().name,
            providers: Object.keys(providers).sort().join(","),
            accounts: accountsVm.accounts.length
        })
    }

    NotesViewModel {
        id: notesVm
        accounts: accountsVm
        cache: notesCache
        analytics: analytics
        syncInterval: Plasmoid.configuration.syncInterval
        railCollapsed: Plasmoid.configuration.railCollapsed
        // The View toggles the property directly; persist it per widget instance.
        onRailCollapsedChanged: Plasmoid.configuration.railCollapsed = railCollapsed
        mixedOrder: Plasmoid.configuration.mixedOrder
        linkPreviews: Plasmoid.configuration.linkPreviews
        onMixedOrderChanged: Plasmoid.configuration.mixedOrder = mixedOrder
    }

    NoteEditorViewModel {
        id: editorVm
        notes: notesVm
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
            anchors.margins: Kirigami.Units.largeSpacing
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
            // The form sits in a card with the usual KDE margins instead of touching the widget edges.
            Item {
                SignInView {
                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.gridUnit
                    accounts: accountsVm
                }
            }
        }

        Component {
            id: notesRoot
            // Inside a Component the object's own property wins over an id of the outer file, so
            // `accountsVm: accountsVm` would bind the property to itself: pass them through root.
            NotesRoot { vm: notesVm; accountsVm: root.accountsModel; editor: editorVm; analyticsVm: root.analyticsModel; updateVm: root.updateModel }
        }
    }
}
