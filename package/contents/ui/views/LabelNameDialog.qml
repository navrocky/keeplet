import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

// Asks for the name of a label (new or renamed). Presentation only: `check(name)` is the ViewModel's
// labelNameError ("" | "empty" | "exists"); the dialog turns the code into text and emits `submitted`.
Kirigami.PromptDialog {
    id: dialog

    property string initialName: ""
    property var check: function (name) { return "" }
    signal submitted(string name)

    readonly property string error: visible ? check(field.text) : ""

    function errorText(code) {
        switch (code) {
        case "exists": return i18n("A label with this name already exists.")
        default: return ""
        }
    }

    function _refreshOk() {
        var ok = standardButton(Kirigami.Dialog.Ok)
        if (ok)
            ok.enabled = error === ""
    }

    standardButtons: Kirigami.Dialog.Ok | Kirigami.Dialog.Cancel
    onErrorChanged: _refreshOk()
    onOpened: {
        field.text = initialName
        field.forceActiveFocus()
        field.selectAll()
        _refreshOk()
    }
    onAccepted: submitted(field.text)

    mainItem: ColumnLayout {
        spacing: Kirigami.Units.smallSpacing

        QQC2.TextField {
            id: field
            Layout.fillWidth: true
            placeholderText: i18n("Label name")
            onAccepted: if (dialog.error === "") dialog.accept()
        }

        QQC2.Label {
            Layout.fillWidth: true
            visible: text !== ""
            text: dialog.errorText(dialog.error)
            color: Kirigami.Theme.negativeTextColor
            wrapMode: Text.Wrap
        }
    }
}
