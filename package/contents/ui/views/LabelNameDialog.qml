import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

// A small modal card over the widget: asks for a label name (new or renamed), or, with showInput off,
// only asks to confirm. Presentation only: `check(name)` is the ViewModel's labelNameError
// ("" | "empty" | "exists"); the card turns the code into text and emits `submitted`.
// It is a plain item on the window overlay, not a Popup: a Popup is clipped and slow inside the small widget window.
Item {
    id: dialog

    property string title: ""
    property string message: ""
    property bool showInput: true
    property string initialName: ""
    property string okText: i18n("OK")
    property var check: function (name) { return "" }
    signal submitted(string name)

    readonly property string error: showInput && visible ? check(field.text) : ""

    function errorText(code) {
        return code === "exists" ? i18n("A label with this name already exists.") : ""
    }

    function open() {
        field.text = initialName
        // Moved onto the window overlay now: before the item is in a window there is no overlay.
        if (QQC2.Overlay.overlay)
            parent = QQC2.Overlay.overlay
        visible = true
        Qt.callLater(function () {
            if (showInput) {
                field.forceActiveFocus()
                field.selectAll()
            } else {
                okButton.forceActiveFocus()
            }
        })
    }
    function close() { visible = false }
    function _accept() {
        if (error !== "")
            return
        visible = false
        submitted(field.text)
    }

    x: 0
    y: 0
    width: parent ? parent.width : 0
    height: parent ? parent.height : 0
    visible: false
    z: 1000
    focus: visible
    Keys.onEscapePressed: close()

    // Dimmed backdrop: a click outside the card cancels.
    Rectangle {
        anchors.fill: parent
        color: Qt.alpha(Kirigami.Theme.backgroundColor, 0.6)
        MouseArea { anchors.fill: parent; onClicked: dialog.close() }
    }

    Kirigami.ShadowedRectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(parent.width - Kirigami.Units.gridUnit * 2, Kirigami.Units.gridUnit * 20)
        height: layout.implicitHeight + Kirigami.Units.gridUnit * 2
        radius: Kirigami.Units.cornerRadius
        color: Kirigami.Theme.backgroundColor
        border.width: 1
        border.color: Qt.alpha(Kirigami.Theme.textColor, 0.2)
        shadow.size: Kirigami.Units.gridUnit
        shadow.color: Qt.rgba(0, 0, 0, 0.35)
        shadow.yOffset: 2

        MouseArea { anchors.fill: parent }   // clicks on the card do not reach the backdrop

        ColumnLayout {
            id: layout
            anchors.fill: parent
            anchors.margins: Kirigami.Units.gridUnit
            spacing: Kirigami.Units.largeSpacing

            Kirigami.Heading {
                Layout.fillWidth: true
                level: 3
                text: dialog.title
                wrapMode: Text.Wrap
            }

            QQC2.Label {
                Layout.fillWidth: true
                visible: dialog.message !== ""
                text: dialog.message
                wrapMode: Text.Wrap
            }

            QQC2.TextField {
                id: field
                Layout.fillWidth: true
                visible: dialog.showInput
                placeholderText: i18n("Label name")
                onAccepted: dialog._accept()
            }

            QQC2.Label {
                Layout.fillWidth: true
                visible: text !== ""
                text: dialog.errorText(dialog.error)
                color: Kirigami.Theme.negativeTextColor
                wrapMode: Text.Wrap
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                Item { Layout.fillWidth: true }

                QQC2.Button {
                    text: i18n("Cancel")
                    icon.name: "dialog-cancel"
                    onClicked: dialog.close()
                }
                QQC2.Button {
                    id: okButton
                    text: dialog.okText
                    icon.name: "dialog-ok"
                    enabled: dialog.error === "" && (!dialog.showInput || field.text.trim() !== "")
                    onClicked: dialog._accept()
                    Keys.onReturnPressed: dialog._accept()
                }
            }
        }
    }
}
