import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

// Sign-in form built from the provider's credentialFields. Presentation only.
ColumnLayout {
    id: view

    required property var accounts   // AccountsViewModel

    readonly property var provider: accounts.providers.length > 0
                                    ? accounts.providers[Math.max(0, providerCombo.currentIndex)] : null
    property var values: ({})

    spacing: Kirigami.Units.largeSpacing

    function errorText(code, detail) {
        switch (code) {
        case "": return ""
        case "network": return i18n("Can't reach the service. Check your connection.")
        case "badCredentials": return i18n("The service rejected these credentials. Get a new token and try again.")
        default: return i18n("Sign-in failed: %1", detail)
        }
    }

    // Provider-specific instructions live here because they are user-facing text.
    function helpText(p) {
        if (p && p.id === "keep") {
            return i18n("1. Open <a href=\"%1\">accounts.google.com/EmbeddedSetup</a> in your browser and sign in.<br/>"
                        + "2. Open developer tools (F12) → Application/Storage → Cookies.<br/>"
                        + "3. Copy the value of the <b>oauth_token</b> cookie and paste it below.",
                        p.signInHelpUrl)
        }
        return ""
    }

    Kirigami.Heading {
        Layout.fillWidth: true
        level: 2
        text: view.accounts.signedIn ? i18n("Add an account") : i18n("Sign in")
        wrapMode: Text.Wrap
    }

    QQC2.ComboBox {
        id: providerCombo
        Layout.fillWidth: true
        visible: view.accounts.providers.length > 1
        model: view.accounts.providers
        textRole: "name"
        enabled: !view.accounts.busy
        onCurrentIndexChanged: view.values = ({})
    }

    PlasmaComponents.Label {
        Layout.fillWidth: true
        visible: text !== ""
        wrapMode: Text.Wrap
        textFormat: Text.StyledText
        text: view.helpText(view.provider)
        onLinkActivated: link => Qt.openUrlExternally(link)

        HoverHandler {
            cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor
        }
    }

    Repeater {
        id: fields
        model: view.provider ? view.provider.credentialFields : []

        PlasmaComponents.TextField {
            required property var modelData
            Layout.fillWidth: true
            placeholderText: i18n(modelData.label)
            echoMode: modelData.secret ? TextInput.Password : TextInput.Normal
            enabled: !view.accounts.busy
            onTextChanged: {
                var v = view.values
                v[modelData.key] = text
                view.values = v
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true

        PlasmaComponents.Button {
            text: i18n("Sign In")
            icon.name: "go-next"
            enabled: !view.accounts.busy && view.provider !== null
                     && view.provider.credentialFields.every(function (f) {
                         return String(view.values[f.key] || "").trim() !== ""
                     })
            onClicked: {
                view.accounts.signIn(view.provider.id, view.values)
                for (var i = 0; i < fields.count; ++i) {
                    var field = fields.itemAt(i)
                    if (field.modelData.secret)
                        field.clear()
                }
            }
        }

        PlasmaComponents.Button {
            visible: view.accounts.signedIn
            text: i18n("Cancel")
            onClicked: view.accounts.cancelSignIn()
        }

        PlasmaComponents.BusyIndicator {
            Layout.preferredHeight: Kirigami.Units.gridUnit * 2
            Layout.preferredWidth: Kirigami.Units.gridUnit * 2
            visible: view.accounts.busy
            running: visible
        }
    }

    Kirigami.InlineMessage {
        Layout.fillWidth: true
        type: Kirigami.MessageType.Error
        text: view.errorText(view.accounts.error, view.accounts.errorDetail)
        visible: text !== ""
    }

    Item { Layout.fillHeight: true }
}
