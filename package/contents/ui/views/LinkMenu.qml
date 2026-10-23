import QtQuick
import org.kde.plasma.extras as PlasmaExtras
import "links.js" as Links

// Context menu of a link in a note (web, e-mail, phone): open it or copy its address. One per screen, shared by its LinkLayers.
Item {
    id: root

    property string url: ""
    readonly property string kind: Links.kind(url)

    // The menu is a window of its own (native look, shadow); it opens at the pointer.
    function openFor(link, item, position) {
        url = link
        menu.visualParent = item
        menu.open(Math.round(position.x), Math.round(position.y))
    }

    PlasmaExtras.Menu {
        id: menu

        PlasmaExtras.MenuItem {
            text: root.kind === "phone" ? i18n("Call") : root.kind === "email" ? i18n("Send e-mail") : i18n("Open link")
            icon: root.kind === "phone" ? "call-start" : root.kind === "email" ? "mail-message-new" : "internet-web-browser"
            onClicked: Qt.openUrlExternally(root.url)
        }
        PlasmaExtras.MenuItem {
            text: root.kind === "phone" ? i18n("Copy phone number")
                : root.kind === "email" ? i18n("Copy e-mail address") : i18n("Copy link address")
            icon: "edit-copy"
            onClicked: {
                clipboard.text = Links.address(root.url)
                clipboard.selectAll()
                clipboard.copy()
                clipboard.text = ""
            }
        }
    }

    // Hidden field used only to reach the clipboard (plain QML has no clipboard API).
    TextEdit { id: clipboard; visible: false }
}
