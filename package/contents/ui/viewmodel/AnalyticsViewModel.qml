import QtQuick

// Consent to anonymous usage statistics: whether to ask, and the commands of the banner and the settings.
// Dependency: `service` (services/Analytics.qml or a stand-in with configured, ready, consent, setConsent).
QtObject {
    id: vm

    required property var service

    // Statistics can be sent by this build at all (the keys are compiled in).
    readonly property bool available: service.configured
    // Not decided yet: the View shows the question.
    readonly property bool askConsent: service.configured && service.ready && service.consent === ""
    readonly property bool enabled: service.enabled

    function allow() { service.setConsent(true) }
    function decline() { service.setConsent(false) }
    function setEnabled(on) { service.setConsent(!!on) }
}
