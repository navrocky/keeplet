import QtQuick

// Opens the update dialog (UpdateDialog.qml); when org.kde.newstuff is missing, the store page instead.
QtObject {
    id: installer

    required property var vm    // UpdateViewModel

    property var _component: null
    property var _dialog: null

    function open() {
        if (_dialog) {
            _dialog.raise()
            return _dialog.requestActivate()
        }
        if (!_component)
            _component = Qt.createComponent("UpdateDialog.qml")
        if (_component.status !== Component.Ready) {
            console.info("Keeplet: update dialog unavailable:", _component.errorString().split("\n")[0])
            return Qt.openUrlExternally(vm.storeUrl)
        }
        _dialog = _component.createObject(null, { vm: vm })
        _dialog.closing.connect(function () {
            var d = _dialog
            _dialog = null
            d.destroy(1000)
        })
    }
}
