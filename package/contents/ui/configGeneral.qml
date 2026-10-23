import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

// Account entries (email, androidId, secretFallback) are deliberately not declared as cfg_*:
// the dialog writes every cfg_* back on Apply and would resurrect a token after sign-out.
KCM.SimpleKCM {
    property alias cfg_syncInterval: syncInterval.value
    property alias cfg_linkPreviews: linkPreviews.checked

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
    }
}
