import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

// Hosts the notes list and the open-note screen and animates between them.
// Navigation state lives in NotesViewModel (currentNoteKey); this only follows it.
QQC2.StackView {
    id: stack

    required property var vm          // NotesViewModel
    required property var accountsVm  // AccountsViewModel
    required property var editor      // NoteEditorViewModel
    property var analyticsVm: null    // AnalyticsViewModel
    property var updateVm: null       // UpdateViewModel

    readonly property bool noteOpen: vm.currentNoteKey !== ""
    readonly property int duration: Kirigami.Units.longDuration

    initialItem: listScreen
    clip: true

    // The preview of web links, shared by both screens. Not named linkPreview: inside the Components below
    // `linkPreview: linkPreview` would bind the screens' own property to itself.
    LinkPreview {
        id: sharedPreview
        active: stack.vm.linkPreviews
        onShown: stack.vm.linkPreviewShown()
    }

    onNoteOpenChanged: {
        sharedPreview.dismiss()
        if (noteOpen)
            push(noteScreen)
        else if (depth > 1)
            pop()
    }

    Component {
        id: listScreen
        NotesScreen { vm: stack.vm; accountsVm: stack.accountsVm; analyticsVm: stack.analyticsVm; updateVm: stack.updateVm; linkPreview: sharedPreview }
    }

    Component {
        id: noteScreen
        NoteScreen { vm: stack.vm; editor: stack.editor; linkPreview: sharedPreview }
    }

    // Forward: new screen slides in from the right while the list fades away; Back: the reverse.
    pushEnter: Transition {
        ParallelAnimation {
            NumberAnimation { property: "x"; from: stack.width * 0.25; to: 0; duration: stack.duration; easing.type: Easing.OutCubic }
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: stack.duration }
        }
    }
    pushExit: Transition {
        ParallelAnimation {
            NumberAnimation { property: "x"; from: 0; to: -stack.width * 0.1; duration: stack.duration; easing.type: Easing.OutCubic }
            NumberAnimation { property: "opacity"; from: 1; to: 0; duration: stack.duration }
        }
    }
    popEnter: Transition {
        ParallelAnimation {
            NumberAnimation { property: "x"; from: -stack.width * 0.1; to: 0; duration: stack.duration; easing.type: Easing.OutCubic }
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: stack.duration }
        }
    }
    popExit: Transition {
        ParallelAnimation {
            NumberAnimation { property: "x"; from: 0; to: stack.width * 0.25; duration: stack.duration; easing.type: Easing.OutCubic }
            NumberAnimation { property: "opacity"; from: 1; to: 0; duration: stack.duration }
        }
    }
}
