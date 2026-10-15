import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami
import "../viewmodel"

ColumnLayout {
    id: view

    required property AuthViewModel auth

    spacing: Kirigami.Units.largeSpacing

    function errorText(code, detail) {
        switch (code) {
        case "": return ""
        case "network": return i18n("Can't reach Google. Check your connection.")
        case "badToken": return i18n("Google rejected the token. Get a new oauth_token and try again.")
        case "sessionExpired": return i18n("Your Google session has expired. Please sign in again.")
        case "storage": return i18n("Can't read the saved key: %1", detail)
        default: return i18n("Sign-in failed: %1", detail)
        }
    }

    Kirigami.Heading {
        Layout.fillWidth: true
        level: 2
        text: i18n("Sign in to Google Keep")
        wrapMode: Text.Wrap
    }

    PlasmaComponents.Label {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        textFormat: Text.StyledText
        text: i18n("1. Open <a href=\"%1\">accounts.google.com/EmbeddedSetup</a> in your browser and sign in.<br/>"
                   + "2. Open developer tools (F12) → Application/Storage → Cookies.<br/>"
                   + "3. Copy the value of the <b>oauth_token</b> cookie and paste it below.",
                   "https://accounts.google.com/EmbeddedSetup")
        onLinkActivated: link => Qt.openUrlExternally(link)

        HoverHandler {
            cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor
        }
    }

    PlasmaComponents.TextField {
        id: emailField
        Layout.fillWidth: true
        placeholderText: i18n("Google e-mail")
        inputMethodHints: Qt.ImhEmailCharactersOnly | Qt.ImhNoAutoUppercase
        enabled: !view.auth.busy
    }

    PlasmaComponents.TextField {
        id: tokenField
        Layout.fillWidth: true
        placeholderText: i18n("oauth_token")
        echoMode: TextInput.Password
        enabled: !view.auth.busy
        onAccepted: signInButton.clicked()
    }

    RowLayout {
        Layout.fillWidth: true

        PlasmaComponents.Button {
            id: signInButton
            text: i18n("Sign In")
            icon.name: "go-next"
            enabled: !view.auth.busy && emailField.text.trim() !== "" && tokenField.text.trim() !== ""
            onClicked: {
                view.auth.signIn(emailField.text, tokenField.text)
                tokenField.clear()
            }
        }

        PlasmaComponents.BusyIndicator {
            Layout.preferredHeight: signInButton.height
            Layout.preferredWidth: signInButton.height
            visible: view.auth.busy
            running: visible
        }
    }

    Kirigami.InlineMessage {
        Layout.fillWidth: true
        type: Kirigami.MessageType.Error
        text: view.errorText(view.auth.error, view.auth.errorDetail)
        visible: text !== ""
    }

    Item { Layout.fillHeight: true }
}
