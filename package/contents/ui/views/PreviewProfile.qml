import QtWebEngine

// Web profile of link previews and of the site sign-in window: kept on disk, so a sign-in made with "Sign in…"
// shows in later previews. Created only through previewProfile.js (one per process).
WebEngineProfile {
    storageName: "keeplet-preview"
    offTheRecord: false
    persistentCookiesPolicy: WebEngineProfile.AllowPersistentCookies
}
