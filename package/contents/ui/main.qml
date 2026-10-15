import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    Plasmoid.icon: "knotes"

    fullRepresentation: ColumnLayout {
        Layout.preferredWidth: Kirigami.Units.gridUnit * 20
        Layout.preferredHeight: Kirigami.Units.gridUnit * 24

        PlasmaComponents.Label {
            Layout.alignment: Qt.AlignCenter
            text: i18n("Keeplet")
        }
    }
}
