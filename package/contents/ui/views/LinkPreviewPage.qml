import QtQuick
import QtWebEngine

// The page shown by LinkPreview; the only view file that imports QtWebEngine, so the widget works without it
// (LinkPreview then shows nothing). A private profile (nothing is stored), muted, no new windows; the page is laid
// out for twice the popup's width and scaled down, so it looks like it does in a browser.
Item {
    id: page

    property string url: ""
    readonly property string title: view.title
    readonly property url icon: view.icon
    readonly property bool loading: view.loading
    property bool failed: false

    WebEngineProfile {
        id: privateProfile
        offTheRecord: true
    }

    WebEngineView {
        id: view
        anchors.fill: parent
        profile: privateProfile
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
