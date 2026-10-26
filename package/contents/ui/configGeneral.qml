import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.plasma.plasmoid
import "viewmodel"
import "services"

// Account entries (email, androidId, secretFallback) are deliberately not declared as cfg_*:
// the dialog writes every cfg_* back on Apply and would resurrect a token after sign-out.
KCM.SimpleKCM {
    property alias cfg_syncInterval: syncInterval.value
    property alias cfg_linkPreviews: linkPreviews.checked
    property alias cfg_checkUpdates: checkUpdates.checked

    // Consent to usage statistics is global (all widgets), so it is not a cfg_* entry either: it is stored in the
    // shared database at once, like the accounts (see configAccounts.qml).
    LocalDb { id: localDb }
    Analytics { id: analytics; db: localDb }
    AnalyticsViewModel { id: analyticsVm; service: analytics }

    Kirigami.FormLayout {
        QQC2.SpinBox {
            id: syncInterval
            Kirigami.FormData.label: i18n("Sync every:")
            from: 1
            to: 120
            textFromValue: (value, locale) => i18np("%1 minute", "%1 minutes", value)
            valueFromText: (text, locale) => parseInt(text)
        }
        QQC2.CheckBox {
            id: linkPreviews
            Kirigami.FormData.label: i18n("Links:")
            text: i18n("Show a preview of a web page when the pointer rests on its link")
        }
        QQC2.Label {
            visible: forgetSignIns.visible
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            text: i18n("“Sign in” in a preview opens the site in a window; the sign-in is kept for later previews.")
        }
        QQC2.Button {
            id: forgetSignIns
            // Previews need QtWebEngine.
            visible: Qt.createComponent("views/PreviewProfile.qml").status === Component.Ready
            property bool done: false
            icon.name: done ? "dialog-ok" : "edit-clear-history"
            text: done ? i18n("Signed out of all sites") : i18n("Forget sign-ins on sites")
            enabled: !done
            onClicked: {
                // The widget does it: see main.qml.
                Plasmoid.configuration.forgetSiteSignIns = Plasmoid.configuration.forgetSiteSignIns + 1
                done = true
            }
        }
        QQC2.CheckBox {
            id: checkUpdates
            Kirigami.FormData.label: i18n("Updates:")
            text: i18n("Tell me when a new version is out")
        }
        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            text: i18n("Checks the version on store.kde.org once a day.")
        }
        QQC2.CheckBox {
            id: statistics
            visible: analyticsVm.available
            Kirigami.FormData.label: i18n("Statistics:")
            text: i18n("Send anonymous usage statistics")
            checked: analyticsVm.enabled
            onToggled: {
                analyticsVm.setEnabled(checked)
                localDb.drain()
            }
        }
        QQC2.Label {
            visible: analyticsVm.available
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            text: i18n("Which features are used and which errors happen, with the widget version and language. Note contents, labels and account details are never sent.")
        }
    }
}
