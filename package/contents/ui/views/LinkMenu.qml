import QtQuick
import org.kde.plasma.extras as PlasmaExtras
import "links.js" as Links

// Context menu of a link in a note: open it or copy its address. One per screen, shared by its LinkLayers.
Item {
    id: root

    property string url: ""

    // The menu is a window of its own (native look, shadow); it opens at the pointer.
    function openFor(link, item, position) {
        url = link
        menu.visualParent = item
        menu.open(Math.round(position.x), Math.round(position.y))
    }

    PlasmaExtras.Menu {
        id: menu

        PlasmaExtras.MenuItem {
            text: i18n("Open link")
            icon: "internet-web-browser"
            onClicked: Qt.openUrlExternally(root.url)
        }
        PlasmaExtras.MenuItem {
            text: i18n("Copy link address")
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
