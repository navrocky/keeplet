import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

// Account entries (email, androidId, secretFallback) are deliberately not declared as cfg_*:
// the dialog writes every cfg_* back on Apply and would resurrect a token after sign-out.
KCM.SimpleKCM {
    property alias cfg_syncInterval: syncInterval.value

    Kirigami.FormLayout {
        QQC2.SpinBox {
            id: syncInterval
            Kirigami.FormData.label: i18n("Sync every:")
            from: 1
            to: 120
            textFromValue: (value, locale) => i18np("%1 minute", "%1 minutes", value)
            valueFromText: (text, locale) => parseInt(text)
        }
    }
}
