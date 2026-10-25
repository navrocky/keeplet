import QtQuick
import "../../code/core/updates.js" as Updates

// A newer version of the widget: whether to show the notice, and its commands.
// Dependency: `service` (services/UpdateCheck.qml or a stand-in with enabled, latest, dismissed, dismiss).
QtObject {
    id: vm

    required property var service
    property string currentVersion: ""

    readonly property string latestVersion: service.latest
    readonly property bool available: service.enabled && Updates.isNewer(service.latest, currentVersion)
                                      && service.dismissed !== service.latest
    // Installed from the update dialog: the new code runs only once Plasma loads the widget again.
    property bool installed: false

    // For the View's install dialog (KNewStuff) and its fallback, the store page.
    readonly property string providerId: Updates.PROVIDER_ID
    readonly property string productId: Updates.PRODUCT_ID
    readonly property string storeUrl: Updates.STORE_URL

    function dismiss() { service.dismiss(service.latest) }
    function markInstalled() { installed = true }
}
