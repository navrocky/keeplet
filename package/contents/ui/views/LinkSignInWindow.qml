import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import QtWebEngine
import "previewProfile.js" as PreviewProfile

// A site in a window of its own, in the profile of link previews: what the user signs in to here, previews show
// signed in. Opened by LinkPreview ("Sign in…"); destroys itself when closed.
Window {
    id: win

    required property string url

    width: Kirigami.Units.gridUnit * 50
    height: Kirigami.Units.gridUnit * 40
    title: view.title !== "" ? view.title : url
    color: Kirigami.Theme.backgroundColor
    visible: true

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        WebEngineView {
            id: view
            Layout.fillWidth: true
            Layout.fillHeight: true
            profile: PreviewProfile.get()
            url: win.url
            // Single sign-on pages often open a window of their own: keep everything in this one.
            onNewWindowRequested: request => request.openIn(view)
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.margins: Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.largeSpacing

            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: i18n("Sign in to the site, then close this window: link previews will show its pages signed in.")
            }
            QQC2.Button {
                icon.name: "dialog-ok"
                text: i18n("Done")
                onClicked: win.close()
            }
        }
    }

    onClosing: win.destroy()
}
