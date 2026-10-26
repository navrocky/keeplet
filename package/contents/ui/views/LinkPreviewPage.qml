import QtQuick
import QtWebEngine
import "previewProfile.js" as PreviewProfile

// The page shown by LinkPreview; loaded on demand, so the widget works without QtWebEngine (LinkPreview then shows
// nothing). The preview profile keeps the sign-ins made with "Sign in…"; muted, no new windows; the page is laid
// out for twice the popup's width and scaled down, so it looks like it does in a browser.
Item {
    id: page

    property string url: ""
    readonly property string title: view.title
    readonly property url icon: view.icon
    readonly property bool loading: view.loading
    property bool failed: false

    WebEngineView {
        id: view
        anchors.fill: parent
        profile: PreviewProfile.get()
        zoomFactor: 0.5
        audioMuted: true
        url: page.url !== "" ? page.url : "about:blank"
        settings.javascriptCanOpenWindows: false
        settings.playbackRequiresUserGesture: true
        settings.focusOnNavigationEnabled: false
        settings.showScrollBars: false

        onLoadingChanged: info => {
            if (info.status === WebEngineView.LoadStartedStatus)
                page.failed = false
            else if (info.status === WebEngineView.LoadFailedStatus && info.url.toString() === page.url)
                page.failed = true
        }
        // A page that wants a new window (target="_blank", window.open after a click) gets the browser.
        onNewWindowRequested: request => Qt.openUrlExternally(request.requestedUrl)
    }
}
