.pragma library

// The web profile of link previews, one per process. Every widget runs in plasmashell's shared QML engine, so this
// library is shared too; QtWebEngine can't open one storage from two profiles (a second one hangs or comes back
// null), so the profile is created here once and never destroyed.
var _profile = null

// The profile (PreviewProfile.qml), created on first use; null when QtWebEngine is missing.
function get() {
    if (!_profile) {
        var c = Qt.createComponent("PreviewProfile.qml")
        if (c.status === 1 /* Component.Ready */)
            _profile = c.createObject(null)
    }
    return _profile
}
