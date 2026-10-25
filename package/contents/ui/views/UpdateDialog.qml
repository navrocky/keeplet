import QtQuick
import org.kde.newstuff as NewStuff

// Plasma's own "Get New Widgets" dialog opened on Keeplet's store entry: it installs the new version
// through KPackage and records it, so Discover offers the later updates too. The only user of
// org.kde.newstuff, loaded by UpdateInstaller.qml.
NewStuff.Dialog {
    id: dialog

    required property var vm    // UpdateViewModel

    configFile: "plasmoids.knsrc"

    onEntryEvent: function (entry, event) {
        if (event === NewStuff.Entry.StatusChangedEvent && entry.uniqueId === vm.productId
                && entry.status === NewStuff.Entry.Installed)
            vm.markInstalled()
    }

    Component.onCompleted: {
        open()
        showEntryDetails(vm.providerId, vm.productId)
    }
}
