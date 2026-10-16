import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

// Accounts page of the settings dialog: the signed-in accounts and the form to add one.
// Presentation only: commands go through the AccountsViewModel.
ColumnLayout {
    id: view

    required property var accounts   // AccountsViewModel
    // The accounts were added or removed here (the running widgets must reload them).
    signal accountsModified()

    property var _pendingRemoval: null   // account asked to sign out, waiting for the confirmation

    spacing: Kirigami.Units.largeSpacing

    function statusText(account) {
        return account.needsSignIn ? i18n("Needs to be signed in again") : i18n("Signed in")
    }

    function removalText(account) {
        if (!account)
            return ""
        if (account.capabilities && account.capabilities.persistent) {
            return i18n("Notebook “%1” and ALL its notes will be deleted from this computer. This cannot be undone.",
                        account.displayName)
        }
        return i18n("Sign out of %1? Its notes are kept in the service; only the data cached on this computer is removed.",
                    account.displayName)
    }

    Kirigami.PlaceholderMessage {
        Layout.fillWidth: true
        visible: view.accounts.accounts.length === 0 && !view.accounts.signInRequested
        text: i18n("No accounts yet")
        explanation: i18n("Add a Google Keep account, or a notebook that is stored only on this computer.")
        icon.name: "user-identity"
    }

    Repeater {
        model: view.accounts.accounts

        RowLayout {
            id: row
            required property var modelData
            Layout.fillWidth: true
            spacing: Kirigami.Units.largeSpacing

            Kirigami.Icon {
                source: row.modelData.icon
                Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                Layout.preferredHeight: Kirigami.Units.iconSizes.medium
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                QQC2.Label {
                    Layout.fillWidth: true
                    text: row.modelData.displayName
                    font.bold: true
                    elide: Text.ElideRight
                }
                QQC2.Label {
                    Layout.fillWidth: true
                    text: row.modelData.providerName + " · " + view.statusText(row.modelData)
                    color: row.modelData.needsSignIn ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.disabledTextColor
                    elide: Text.ElideRight
                }
            }

            QQC2.Button {
                visible: row.modelData.needsSignIn
                text: i18n("Sign In Again")
                icon.name: "view-refresh"
                onClicked: view.accounts.requestSignIn({ providerId: row.modelData.providerId,
                                                         accountId: row.modelData.accountId })
            }

            QQC2.Button {
                text: row.modelData.capabilities && row.modelData.capabilities.persistent ? i18n("Delete") : i18n("Sign Out")
                icon.name: row.modelData.capabilities && row.modelData.capabilities.persistent ? "edit-delete" : "system-log-out"
                onClicked: { view._pendingRemoval = row.modelData; confirm.open() }
            }
        }
    }

    QQC2.Button {
        visible: !view.accounts.signInRequested
        text: i18n("Add Account…")
        icon.name: "list-add"
        onClicked: view.accounts.requestSignIn()
    }

    Kirigami.Separator {
        Layout.fillWidth: true
        visible: view.accounts.signInRequested
    }

    SignInView {
        Layout.fillWidth: true
        visible: view.accounts.signInRequested
        accounts: view.accounts
        embedded: true
    }

    Item { Layout.fillHeight: true }

    Kirigami.PromptDialog {
        id: confirm
        title: view._pendingRemoval && view._pendingRemoval.capabilities && view._pendingRemoval.capabilities.persistent
               ? i18n("Delete notebook") : i18n("Sign out")
        subtitle: view.removalText(view._pendingRemoval)
        standardButtons: Kirigami.Dialog.Ok | Kirigami.Dialog.Cancel
        onAccepted: {
            var key = view._pendingRemoval.key
            view._pendingRemoval = null
            view.accounts.remove(key).then(function () { view.accountsModified() })
        }
        onRejected: view._pendingRemoval = null
    }

    // A finished sign-in clears signInRequested: tell the widgets.
    Connections {
        target: view.accounts
        function onSignInRequestedChanged() {
            if (!view.accounts.signInRequested && !view.accounts.busy && view.accounts.error === "")
                view.accountsModified()
        }
    }
}
