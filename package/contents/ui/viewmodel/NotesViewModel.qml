import QtQuick
import "../../code/core/workspace.js" as Workspace
import "../../code/core/checklist.js" as Checklist

// ViewModel for the notes list across all accounts shown by this widget.
// Owns per-account provider state, exposes the merged and filtered notes and the commands.
// No visual items and no user-facing strings: errors are codes (View translates them).
//
// Dependencies: `accounts` (needs `sessions`, see AccountsViewModel) and optional `cache`
// ({load(key), save(key, json), remove(key)}).
QtObject {
    id: vm

    required property var accounts
    property var cache: null
    property int syncInterval: 5 // minutes
    // Pause after the last edit before queued edits are sent (ms); tests shorten it.
    property int writeDelay: 1500

    // --- Output
    property var notes: []        // visible notes, pinned first (see Workspace.visibleNotes)
    property var labels: []       // labels of all shown accounts, each with accountKey and key
    property bool syncing: false  // any account is syncing
    property bool loaded: false   // there is something to show (cache or server)
    property var lastSync: null   // Date of the latest successful sync, or null
    // Local edits not yet accepted by their servers (all accounts). They stay visible and survive restarts.
    property int unsynced: 0
    // Per-account problems: [{accountKey, displayName, kind, detail}], kind is a ProviderError kind.
    property var errors: []
    // Convenience for single-account Views: the first problem, or "".
    readonly property string error: errors.length > 0 ? errors[0].kind : ""
    readonly property string errorDetail: errors.length > 0 ? errors[0].detail : ""

    // Navigation items for the label rail, built here so the View only renders them:
    //   {type: "header", accountKey, name, icon}
    //   {type: "group", key, kind: "all"|"unlabeled"|"label"|"archive"|"trash", name (labels only),
    //    icon, count, accountKey, droppable}
    // Built-in group names are user-facing text, so the View derives them from `kind`.
    property var rail: []
    property bool railVisible: false
    // Account switcher: [{key: "" for all, name, icon}] (the View shows it when there are several accounts).
    property var accountTabs: []

    // --- Input (set by the View)
    property string searchText: ""
    // Selected group: "all" | "unlabeled" | "unlabeled:<accountKey>" | "label:<accountKey>|<labelId>" | "archive" | "trash"
    // The widget's own icon (shown for "All notes").
    readonly property url appIcon: Qt.resolvedUrl("../../icons/keeplet.svg")
    property string selected: "all"
    property string accountFilter: "" // accountKey or "" for all accounts
    property bool railCollapsed: false
    // The user's own order of the mixed list (several accounts): note keys, kept by the widget, not in Keep.
    property var mixedOrder: []

    // --- Navigation
    // Key of the note being created before it has an id (see openNewNote).
    readonly property string draftKey: "<new>"
    property string currentNoteKey: ""  // "<accountKey>/<noteId>" of the open note, or draftKey, or ""
    property var currentNote: null      // the open note (kept fresh on every sync), or null

    // The last undoable action, for a short "Undo" notice in the View:
    //   {kind: "trashed"|"archived"|"unarchived"|"labeled"|"unlabeled", noteKey, label (name, for labeled)}
    property var lastAction: null
    // Account that received the last new note; the default target for the next one.
    property string lastAccountKey: ""
    // Whether at least one account in view can hold a new note (enables the "new note" control).
    readonly property bool canCreate: Object.keys(_accs).some(function (k) { return canWrite(k) })

    // --- Private
    property var draft: null          // a new note that has no id yet
    property string _draftTarget: ""  // key the draft got once it was saved
    property var _undo: null          // function that reverts lastAction, returns whether it did
    property var _accs: ({})          // accountKey -> {account, provider, session, state, syncing, lastSync, error}
    property var _all: []
    readonly property var _sessions: accounts.sessions

    // The cache snapshot is serialized and written to SQLite synchronously (UI thread), so it is done once after
    // a quiet period instead of after every edit. Edits are queued in the state, which is what the snapshot holds:
    // flushCache() runs on destruction, so a close loses nothing.
    property int cacheDelay: 1500
    property var _cacheDirty: ({})
    property Timer _cacheTimer: Timer {
        interval: vm.cacheDelay
        repeat: false
        onTriggered: vm.flushCache()
    }
    function _cacheLater(accountKey) {
        if (!cache)
            return
        _cacheDirty[accountKey] = true
        // The state of a persistent provider (local notes) is the only copy: written at once, not after a quiet period.
        var a = _accs[accountKey]
        if (a && a.provider.capabilities.persistent) {
            flushCache()
            if (typeof cache.flush === "function")
                cache.flush()
            return
        }
        _cacheTimer.restart()
    }
    function flushCache() {
        _cacheTimer.stop()
        var keys = Object.keys(_cacheDirty)
        _cacheDirty = {}
        keys.forEach(function (key) {
            if (cache && _accs[key])
                cache.save(key, JSON.stringify(_accs[key].state))   // queued by the cache, written off the hot path
        })
    }
    // The widget goes away: nothing queued may be lost.
    Component.onDestruction: {
        flushCache()
        if (cache && typeof cache.flush === "function")
            cache.flush()
    }

    property Timer _writeTimer: Timer {
        interval: vm.writeDelay
        repeat: false
        onTriggered: vm._sendPending()
    }

    property Timer _timer: Timer {
        interval: Math.max(1, vm.syncInterval) * 60 * 1000
        repeat: true
        running: vm._sessions.length > 0
        onTriggered: vm.refresh()
    }

    // --- Commands
    function refresh() {
        Object.keys(_accs).forEach(function (key) { _refreshAccount(key) })
    }

    // A note by key ("<accountKey>/<id>") regardless of the selected group, or null. Includes pending local edits.
    function noteByKey(noteKey) {
        if (noteKey === draftKey)
            return _draftTarget ? noteByKey(_draftTarget) : draft
        for (var i = 0; i < _all.length; i++) {
            if (_all[i].key === noteKey)
                return _all[i]
        }
        return null
    }

    // The provider capabilities of an account, or null.
    function capabilities(accountKey) {
        var a = _accs[accountKey]
        return a ? a.provider.capabilities : null
    }

    // Whether notes of this account can be edited (provider capability).
    function canWrite(accountKey) {
        var a = _accs[accountKey]
        return !!a && !a.broken && !!a.provider.capabilities.write && typeof a.session.commit === "function"
    }

    // Applies an edited note (or a new one: empty `id`, `accountKey` of the target account) at once and
    // queues it for the server. Returns the note's key ("<accountKey>/<id>"), or "" if it can't be written.
    function saveNote(note) {
        if (!canWrite(note.accountKey))
            return ""
        var a = _accs[note.accountKey]
        var saved = a.session.commit(a.state, _snapshot(note))
        if (!saved)
            return ""
        var key = Workspace.noteKey(note.accountKey, saved.id)
        lastAccountKey = note.accountKey
        // The open draft becomes this note; the editor keeps its history. Set before the rebuild so
        // currentNote follows the stored note at once.
        if (!note.id && currentNoteKey === draftKey)
            _draftTarget = key
        _afterWrite(a, saved.id)
        return key
    }

    // Deletes a note for good (use saveNote with `trashed` to move it to the trash).
    function removeNote(note) {
        if (!canWrite(note.accountKey))
            return false
        var a = _accs[note.accountKey]
        a.session.remove(a.state, note.id)
        _afterWrite(a)
        return true
    }

    function select(key) { selected = key }
    function selectAccount(accountKey) { accountFilter = accountKey }
    function openNote(noteKey) {
        if (noteKey !== draftKey) {
            draft = null
            _draftTarget = ""
        }
        currentNoteKey = noteKey
    }
    function closeNote() {
        currentNoteKey = ""
        draft = null
        _draftTarget = ""
    }

    // Accounts a note can be created in: [{key, name, icon}].
    function writableAccounts() {
        return Object.keys(_accs).filter(function (k) { return canWrite(k) }).map(function (k) {
            return { key: k, name: _accs[k].account.displayName, icon: _accs[k].provider.icon }
        })
    }

    // Whether labels of this account can be created, renamed and deleted (provider capability).
    function canEditLabels(accountKey) {
        var a = _accs[accountKey]
        return !!a && !a.broken && !!a.provider.capabilities.labelEdit && typeof a.session.createLabel === "function"
    }

    // Why `name` cannot name a label of the account: "" (it can), "empty" or "exists" (another label has it,
    // ignoring case). `exceptLabelId` is the label being renamed. The View turns the code into text.
    function labelNameError(accountKey, name, exceptLabelId) {
        var n = String(name === undefined || name === null ? "" : name).trim().replace(/\s+/g, " ").toLowerCase()
        if (n === "")
            return "empty"
        var taken = labelsOf(accountKey).some(function (l) {
            return l.id !== exceptLabelId && l.name.toLowerCase() === n
        })
        return taken ? "exists" : ""
    }

    // Creates a label in the account; returns {id, name, key} or null (cannot edit, invalid or taken name).
    function createLabel(accountKey, name) {
        if (!canEditLabels(accountKey) || labelNameError(accountKey, name) !== "")
            return null
        var a = _accs[accountKey]
        var made = a.session.createLabel(a.state, name)
        if (!made)
            return null
        _afterWrite(a)
        return { id: made.id, name: made.name, key: Workspace.labelKey(accountKey, made.id) }
    }

    function _labelByKey(labelKey) {
        return labels.filter(function (l) { return l.key === labelKey })[0] || null
    }

    // Renames a label ("<accountKey>|<labelId>"); returns whether it was renamed.
    function renameLabel(labelKey, name) {
        var l = _labelByKey(labelKey)
        if (!l || !canEditLabels(l.accountKey) || labelNameError(l.accountKey, name, l.id) !== "")
            return false
        var a = _accs[l.accountKey]
        if (!a.session.renameLabel(a.state, l.id, name))
            return false
        _afterWrite(a)
        return true
    }

    // Deletes a label from its account; its notes stay, only the label is removed from them.
    function deleteLabel(labelKey) {
        var l = _labelByKey(labelKey)
        if (!l || !canEditLabels(l.accountKey))
            return false
        var a = _accs[l.accountKey]
        if (!a.session.deleteLabel(a.state, l.id))
            return false
        _afterWrite(a)
        return true
    }

    // Labels of one account: [{id, name, key, accountKey}].
    function labelsOf(accountKey) {
        return labels.filter(function (l) { return l.accountKey === accountKey })
    }

    function _newNoteAccount() {
        var writable = writableAccounts().map(function (a) { return a.key })
        if (writable.length === 0)
            return ""
        if (accountFilter && writable.indexOf(accountFilter) >= 0)
            return accountFilter
        if (selected.indexOf("unlabeled:") === 0) {
            var owner = selected.substring("unlabeled:".length)
            if (writable.indexOf(owner) >= 0)
                return owner
        }
        if (selected.indexOf("label:") === 0) {
            var key = selected.substring("label:".length)
            for (var i = 0; i < labels.length; i++) {
                if (labels[i].key === key && writable.indexOf(labels[i].accountKey) >= 0)
                    return labels[i].accountKey
            }
        }
        if (lastAccountKey && writable.indexOf(lastAccountKey) >= 0)
            return lastAccountKey
        return writable.sort()[0]
    }

    // Opens an empty note (type "NOTE" or "LIST") in the editor. It is created on the first change, so closing it
    // untouched leaves nothing behind. The account is the one in view, else the one that got the last note.
    // A new note inside a label group gets that label. Returns false if no account can be written.
    function openNewNote(type) {
        var accountKey = _newNoteAccount()
        if (!accountKey)
            return false
        var preset = []
        if (selected.indexOf("label:") === 0) {
            var key = selected.substring("label:".length)
            labelsOf(accountKey).forEach(function (l) {
                if (l.key === key)
                    preset.push({ id: l.id, name: l.name, key: l.key, accountKey: l.accountKey })
            })
        }
        var list = type === "LIST"
        draft = {
            id: "", key: "", accountKey: accountKey, accountName: _accs[accountKey].account.displayName, providerId: _accs[accountKey].provider.id,
            type: list ? "LIST" : "NOTE", title: "", text: "",
            items: list ? [{ id: "", text: "", checked: false, indent: 0 }] : [],
            images: [], color: "DEFAULT", pinned: false, archived: selected === "archive", trashed: false,
            labels: preset, order: 0, created: "", updated: ""
        }
        _draftTarget = ""
        currentNoteKey = ""      // so that opening a second draft is a change the View and editor see
        currentNoteKey = draftKey
        return true
    }

    // Applies `changes` (any note fields: pinned, archived, trashed, color, labels...) to a note by key.
    function updateNote(noteKey, changes) {
        var note = noteByKey(noteKey)
        if (!note)
            return false
        var next = {}
        for (var k in note)
            next[k] = note[k]
        for (var c in changes)
            next[c] = changes[c]
        return saveNote(next) !== ""
    }

    function _remember(kind, note, label) {
        var snapshot = _snapshotOf(note)
        _undo = function () { return saveNote(snapshot) !== "" }
        lastAction = { kind: kind, noteKey: note.key, label: label || "" }
    }

    function _snapshotOf(note) {
        var s = _snapshot(note)
        s.accountKey = note.accountKey
        return s
    }

    // Undoable shortcuts used by the list and its context menu.
    function trashNote(noteKey) {
        var note = noteByKey(noteKey)
        if (!note || !canWrite(note.accountKey))
            return false
        _remember("trashed", note)
        return updateNote(noteKey, { trashed: true })
    }
    function restoreNote(noteKey) { return updateNote(noteKey, { trashed: false }) }
    function archiveNote(noteKey, archived) {
        var note = noteByKey(noteKey)
        if (!note || !canWrite(note.accountKey))
            return false
        _remember(archived ? "archived" : "unarchived", note)
        return updateNote(noteKey, { archived: !!archived })
    }
    function setPinned(noteKey, pinned) { return updateNote(noteKey, { pinned: !!pinned }) }
    function setColor(noteKey, color) { return updateNote(noteKey, { color: color }) }

    // Deletes a note for good, or every note in the trash of the accounts in view.
    function deleteForever(noteKey) {
        var note = noteByKey(noteKey)
        return !!note && removeNote(note)
    }
    function emptyTrash() {
        var count = 0
        _all.filter(function (n) {
            return n.trashed && (!accountFilter || n.accountKey === accountFilter) && canWrite(n.accountKey)
        }).forEach(function (n) {
            if (removeNote(n))
                count++
        })
        return count
    }

    // Reverts lastAction (the note goes back to how it was) and clears it.
    function undoLast() {
        if (!lastAction || !_undo)
            return false
        var revert = _undo
        dismissAction()
        return revert()
    }
    function dismissAction() {
        lastAction = null
        _undo = null
    }

    // --- Manual order
    // The list can be put in a manual order when it shows one account and the provider can reorder (the order
    // is kept in Keep), or when it mixes several accounts (the order is `mixedOrder`, kept by the widget).
    // Never in the trash or while a search filters the list.
    readonly property bool reorderEnabled: _canReorderHere()

    // The one account whose notes the list shows ("" when several are mixed): the account filter, the owner
    // of the selected label / "No label" group, or the only account. Updated with every filter run.
    property string scopeAccountKey: ""
    // Notes of several accounts are listed together: cards show their account.
    property bool showAccounts: false

    function _scopeAccountKey() {
        if (accountFilter)
            return accountFilter
        var keys = Object.keys(_accs)
        if (keys.length === 1)
            return keys[0]
        if (selected.indexOf("unlabeled:") === 0)
            return selected.substring("unlabeled:".length)
        if (selected.indexOf("label:") === 0) {
            var key = selected.substring("label:".length)
            for (var i = 0; i < labels.length; i++) {
                if (labels[i].key === key)
                    return labels[i].accountKey
            }
        }
        return ""
    }

    // Icon of an account's provider (for cards), or "".
    function accountIcon(accountKey) {
        var a = _accs[accountKey]
        return a ? a.provider.icon : ""
    }

    function _canReorderHere() {
        if (searchText.trim() !== "" || selected === "trash")
            return false
        var key = scopeAccountKey
        if (!key)
            return showAccounts
        if (!_accs[key])
            return false
        var a = _accs[key]
        return !!a.provider.capabilities.reorder && canWrite(key) && typeof a.session.reorder === "function"
    }

    function _pinnedCount(list) {
        var n = 0
        while (n < list.length && list[n].pinned)
            n++
        return n
    }

    // The visible list without the note: positions are counted in it ("insert before this index").
    function _without(noteKey) {
        return notes.filter(function (n) { return n.key !== noteKey })
    }

    // Whether the note may be inserted at `index` of the list without it. Pinned notes stay among the
    // pinned ones, the others among the rest (pinning is changed with the pin button).
    function canMoveTo(noteKey, index) {
        if (!reorderEnabled)
            return false
        var note = null
        for (var i = 0; i < notes.length; i++) {
            if (notes[i].key === noteKey)
                note = notes[i]
        }
        if (!note || (scopeAccountKey !== "" && note.accountKey !== scopeAccountKey))
            return false
        var list = _without(noteKey)
        var pinned = _pinnedCount(list)
        var from = note.pinned ? 0 : pinned
        var to = note.pinned ? pinned : list.length
        return index >= from && index <= to
    }

    // The orders to assign so that `note` sits at `index` of `list` (the visible list without it), as
    // [{note, order}]; empty when it already sits there. Neighbours are taken from the same section.
    function _orderPlan(note, list, index) {
        var STEP = 1000000
        var above = index > 0 ? list[index - 1] : null
        var below = index < list.length ? list[index] : null
        if (above && above.pinned !== note.pinned)
            above = null
        if (below && below.pinned !== note.pinned)
            below = null
        if (!above && !below)
            return []
        if ((!above || note.order < above.order) && (!below || note.order > below.order))
            return []                                             // already between its new neighbours
        var value = null
        if (above && below) {
            var mid = Math.floor((above.order + below.order) / 2)
            if (mid < above.order && mid > below.order)
                value = mid
        } else if (above) {
            value = above.order - STEP
        } else {
            value = below.order + STEP
        }
        if (value !== null)
            return [{ note: note, order: value }]
        // No room between the neighbours: give the whole section fresh, evenly spaced orders.
        var section = list.filter(function (n) { return n.pinned === note.pinned })
        var position = index - (note.pinned ? 0 : _pinnedCount(list))
        section.splice(position, 0, note)
        var top = Math.max.apply(null, section.map(function (n) { return n.order })) + STEP
        var plan = []
        section.forEach(function (n, k) {
            var order = top - k * STEP
            if (n.order !== order)
                plan.push({ note: n, order: order })
        })
        return plan
    }

    // Puts a note at `index` of the visible list without it. Undoable. Returns whether anything changed.
    function moveNote(noteKey, index) {
        if (!canMoveTo(noteKey, index))
            return false
        var note = noteByKey(noteKey)
        if (scopeAccountKey === "")
            return _moveInMixed(noteKey, index)
        var plan = _orderPlan(note, _without(noteKey), index)
        if (plan.length === 0)
            return false
        var a = _accs[note.accountKey]
        var previous = plan.map(function (p) { return { id: p.note.id, order: p.note.order } })
        plan.forEach(function (p) { a.session.reorder(a.state, p.note.id, p.order) })
        _undo = function () {
            previous.forEach(function (p) { a.session.reorder(a.state, p.id, p.order) })
            _afterWrite(a)
            return true
        }
        lastAction = { kind: "moved", noteKey: noteKey, label: "" }
        _afterWrite(a)
        return true
    }

    // Mixed list: the visible keys (in their current order) with the note moved to `index` become the
    // new `mixedOrder`; keys of notes that are not visible now keep their place after them.
    function _moveInMixed(noteKey, index) {
        var keys = _without(noteKey).map(function (n) { return Workspace.noteKey(n.accountKey, n.id) })
        keys.splice(index, 0, noteKey)
        var before = notes.map(function (n) { return Workspace.noteKey(n.accountKey, n.id) })
        if (keys.join("\n") === before.join("\n"))
            return false
        var known = {}
        keys.forEach(function (k) { known[k] = true })
        var previous = mixedOrder
        mixedOrder = keys.concat(previous.filter(function (k) { return !known[k] && noteByKey(k) }))
        _undo = function () {
            mixedOrder = previous
            _applyFilter()
            return true
        }
        lastAction = { kind: "moved", noteKey: noteKey, label: "" }
        _applyFilter()
        return true
    }

    // --- Drag & drop of a note onto a rail group
    // The result of dropping, or null when the drop is not allowed / would change nothing.
    function _dropPlan(noteKey, railKey) {
        var note = noteByKey(noteKey)
        if (!note || !canWrite(note.accountKey))
            return null
        var caps = capabilities(note.accountKey)
        if (!caps || caps.labels === "none")
            return null
        if (railKey === "archive" || railKey === "trash") {
            if (railKey === "archive" ? (!caps.archive || note.archived || note.trashed) : (!caps.trash || note.trashed))
                return null
            return { note: note, kind: railKey }
        }
        if (railKey === "unlabeled" || railKey.indexOf("unlabeled:") === 0) {
            // A per-account group only takes notes of that account.
            if (railKey !== "unlabeled" && railKey !== "unlabeled:" + note.accountKey)
                return null
            return note.labels.length === 0 ? null : { note: note, labels: [], kind: "unlabeled", name: "" }
        }
        if (railKey.indexOf("label:") !== 0)
            return null
        var key = railKey.substring("label:".length)
        var target = null
        for (var i = 0; i < labels.length; i++) {
            if (labels[i].key === key)
                target = labels[i]
        }
        // Labels belong to an account: a note can't be put into another account's group.
        if (!target || target.accountKey !== note.accountKey)
            return null
        if (note.labels.some(function (l) { return l.id === target.id }))
            return null
        // Dragged out of a label group: the note moves, so that group's label goes; other labels stay.
        var from = selected.indexOf("label:") === 0 ? selected.substring("label:".length) : ""
        var source = labels.filter(function (l) { return l.key === from && l.accountKey === note.accountKey })[0]
        var kept = source ? note.labels.filter(function (l) { return l.id !== source.id }) : note.labels
        var next = caps.labels === "single" ? [target] : kept.concat([target])
        return { note: note, labels: next, kind: "labeled", name: target.name }
    }

    // Whether dropping `noteKey` on `railKey` is allowed and does something (used to highlight targets).
    function canDrop(noteKey, railKey) {
        return _dropPlan(noteKey, railKey) !== null
    }

    // "Label" groups add the label (dropping the one of the group the note is dragged from; replace it for
    // single-category providers), "No label" removes all
    // labels; All/Archive/Trash and other accounts' labels are refused. Undoable through undoLast.
    function dropNote(noteKey, railKey) {
        var plan = _dropPlan(noteKey, railKey)
        if (!plan)
            return false
        if (plan.kind === "archive")
            return archiveNote(noteKey, true)
        if (plan.kind === "trash")
            return trashNote(noteKey)
        _remember(plan.kind, plan.note, plan.name)
        return updateNote(noteKey, { labels: plan.labels })
    }

    // A note as text for the clipboard ("" for an unknown key): title and body, checklists with "- [x]" marks.
    function noteText(noteKey) {
        var note = noteByKey(noteKey)
        return note ? Checklist.noteText(note) : ""
    }

    // --- Internals
    // Only provider-neutral fields go to the provider; view-only fields (keys, account tags) are dropped.
    function _snapshot(note) {
        return {
            id: note.id || "", type: note.type, title: note.title || "", text: note.text || "",
            items: (note.items || []).map(function (i) {
                return { id: i.id || "", text: i.text, checked: !!i.checked, indent: i.indent || 0 }
            }),
            color: note.color || "DEFAULT", pinned: !!note.pinned, archived: !!note.archived,
            trashed: !!note.trashed,
            labels: (note.labels || []).map(function (l) { return { id: l.id, name: l.name } })
        }
    }

    // `noteId`: the one note that changed; when it is already listed (and the provider can build a single note)
    // only that note is rebuilt, which keeps typing in a big account cheap. Anything else rebuilds everything.
    function _afterWrite(a, noteId) {
        _cacheLater(a.account.key)
        if (noteId === undefined || !_patchNote(a, noteId))
            _rebuild()
        else
            _applyFilter()
        _updateStatus()
        _writeTimer.restart()
    }

    function _pendingOf(a) {
        return typeof a.session.pending === "function" ? a.session.pending(a.state) : 0
    }

    function _sendPending() {
        Object.keys(_accs).forEach(function (key) {
            if (_pendingOf(_accs[key]) > 0)
                _refreshAccount(key)
        })
    }

    function _fail(e) {
        if (e && e.kind)
            return { kind: e.kind, detail: e.detail || "" }
        return { kind: "failed", detail: String(e) }
    }

    function _refreshAccount(key) {
        var a = _accs[key]
        if (!a || a.syncing || a.broken)
            return
        a.syncing = true
        a.error = null
        _updateStatus()
        a.session.sync(a.state, []).then(function (state) {
            a.state = state
            a.lastSync = new Date()
            a.loaded = true
            _cacheLater(key)
        }).catch(function (e) {
            a.error = _fail(e)
        }).then(function () {
            a.syncing = false
            if (_accs[key] === a) { // the account may have been removed meanwhile
                _rebuild()
                _updateStatus()
                // Edits made while this request was in flight are sent next, unless the server is unreachable
                // (then the regular sync timer or a manual refresh retries).
                if (!a.error && _pendingOf(a) > 0)
                    _writeTimer.restart()
            }
        })
    }

    function _updateStatus() {
        var keys = Object.keys(_accs)
        syncing = keys.some(function (k) { return _accs[k].syncing })
        loaded = keys.some(function (k) { return _accs[k].loaded })
        var last = null
        var errs = []
        var queued = 0
        keys.forEach(function (k) {
            var a = _accs[k]
            queued += _pendingOf(a)
            if (a.lastSync && (!last || a.lastSync > last))
                last = a.lastSync
            if (a.error)
                errs.push({ accountKey: k, displayName: a.account.displayName, kind: a.error.kind, detail: a.error.detail })
        })
        lastSync = last
        unsynced = queued
        errors = errs
    }

    function _patchNote(a, noteId) {
        if (typeof a.session.note !== "function")
            return false
        var key = Workspace.noteKey(a.account.key, noteId)
        var at = -1
        for (var i = 0; i < _all.length; i++) {
            if (_all[i].key === key) {
                at = i
                break
            }
        }
        if (at < 0)
            return false
        var fresh = a.session.note(a.state, noteId)
        if (!fresh)
            return false
        var copy = _all.slice()
        copy[at] = Workspace.annotate(a.account, [fresh], []).notes[0]
        _all = copy
        return true
    }

    function _rebuild() {
        var parts = Object.keys(_accs).map(function (k) {
            var a = _accs[k]
            return Workspace.annotate(a.account, a.session.notes(a.state), a.session.labels(a.state))
        })
        var merged = Workspace.merge(parts)
        _all = merged.notes
        labels = merged.labels
        _applyFilter()
    }

    function _selection(key) {
        if (key === "unlabeled")
            return { view: "notes", unlabeled: true }
        if (key.indexOf("unlabeled:") === 0)
            return { view: "notes", unlabeledAccount: key.substring("unlabeled:".length) }
        if (key === "archive")
            return { view: "archive" }
        if (key === "trash")
            return { view: "trash" }
        if (key.indexOf("label:") === 0)
            return { view: "notes", labelKey: key.substring("label:".length) }
        return { view: "notes" }
    }

    function _count(extra) {
        var opts = { accountFilter: accountFilter, accountCount: Object.keys(_accs).length, view: "notes" }
        for (var k in extra)
            opts[k] = extra[k]
        return Workspace.visibleNotes(_all, opts).length
    }

    function _buildRail() {
        var keys = Object.keys(_accs)
        var scope = keys.filter(function (k) { return !accountFilter || k === accountFilter })
                        .map(function (k) { return _accs[k] })
        var multi = keys.length > 1
        var items = []

        function anyCap(fn) { return scope.some(function (a) { return fn(a.provider.capabilities) }) }
        var hasLabels = anyCap(function (c) { return c.labels !== "none" })
        var hasArchive = anyCap(function (c) { return c.archive })
        var hasTrash = anyCap(function (c) { return c.trash })

        items.push({ type: "group", key: "all", kind: "all", icon: appIcon, accountKey: "",
                     count: _count({}), droppable: false })
        if (hasLabels) {
            // With account headers each account has its own "No label" under its header.
            var grouped = multi && !accountFilter
            if (!grouped)
                items.push({ type: "group", key: "unlabeled", kind: "unlabeled", icon: "tag-delete", accountKey: "",
                             count: _count({ unlabeled: true }), droppable: true })
            var inScope = labels.filter(function (l) { return !accountFilter || l.accountKey === accountFilter })
            var byName = function (a, b) { return a.name.localeCompare(b.name) }
            function labelItem(l) {
                var acc = _accs[l.accountKey]
                return { type: "group", key: "label:" + l.key, kind: "label", name: l.name, icon: "tag",
                         accountKey: l.accountKey, count: _count({ labelKey: l.key }), droppable: true,
                         accountName: acc ? acc.account.displayName : "", providerName: acc ? acc.provider.name : "",
                         providerIcon: acc ? acc.provider.icon : "" }
            }
            if (multi && !accountFilter) {
                scope.forEach(function (a) {
                    var own = inScope.filter(function (l) { return l.accountKey === a.account.key }).sort(byName)
                    var editable = canEditLabels(a.account.key)
                    var labeled = a.provider.capabilities.labels !== "none"
                    if (own.length === 0 && !editable && !labeled)
                        return
                    items.push({ type: "header", accountKey: a.account.key, name: a.account.displayName,
                                 icon: a.provider.icon, canAddLabel: editable })
                    if (a.provider.capabilities.labels !== "none")
                        items.push({ type: "group", key: "unlabeled:" + a.account.key, kind: "unlabeled",
                                     icon: "tag-delete", accountKey: a.account.key, droppable: true,
                                     count: _count({ unlabeledAccount: a.account.key }) })
                    own.forEach(function (l) { items.push(labelItem(l)) })
                })
            } else {
                inScope.slice().sort(byName).forEach(function (l) { items.push(labelItem(l)) })
                // One account in view: the place to create its labels.
                if (scope.length === 1 && canEditLabels(scope[0].account.key))
                    items.push({ type: "addLabel", accountKey: scope[0].account.key })
            }
        }
        if (hasArchive)
            items.push({ type: "group", key: "archive", kind: "archive", icon: "archive-insert", accountKey: "",
                         count: _count({ view: "archive" }), droppable: true })
        if (hasTrash)
            items.push({ type: "group", key: "trash", kind: "trash", icon: "user-trash", accountKey: "",
                         count: _count({ view: "trash" }), droppable: true })

        rail = items
        railVisible = items.length > 1
        accountTabs = [{ key: "", name: "", icon: appIcon }].concat(keys.map(function (k) {
            return { key: k, name: _accs[k].account.displayName, icon: _accs[k].provider.icon }
        }))
    }

    // A selection that no longer exists (label or account removed) falls back to everything.
    function _validateSelection() {
        if (accountFilter && !_accs[accountFilter])
            accountFilter = ""
        if (selected.indexOf("unlabeled:") === 0) {
            var owner = selected.substring("unlabeled:".length)
            if (!_accs[owner] || (accountFilter && accountFilter !== owner))
                selected = "all"
        }
        if (selected.indexOf("label:") === 0) {
            var key = selected.substring("label:".length)
            var exists = labels.some(function (l) {
                return l.key === key && (!accountFilter || l.accountKey === accountFilter)
            })
            if (!exists)
                selected = "all"
        }
    }

    function _syncCurrentNote() {
        if (!currentNoteKey) {
            currentNote = null
            return
        }
        var found = noteByKey(currentNoteKey)
        if (found) {
            currentNote = found
        } else {
            currentNote = null
            currentNoteKey = "" // the note vanished (deleted elsewhere)
        }
    }

    function _applyFilter() {
        _validateSelection()
        var sel = _selection(selected)
        scopeAccountKey = _scopeAccountKey()
        showAccounts = Object.keys(_accs).length > 1 && scopeAccountKey === ""
        var opts = { accountFilter: accountFilter, query: searchText, accountCount: Object.keys(_accs).length,
                     singleAccount: scopeAccountKey !== "", manualOrder: mixedOrder }
        for (var k in sel)
            opts[k] = sel[k]
        notes = Workspace.visibleNotes(_all, opts)
        _buildRail()
        _syncCurrentNote()
    }

    // Adopts the session list: new accounts start from their cache and sync, removed ones are dropped.
    function _adoptSessions() {
        var next = {}
        var fresh = []
        _sessions.forEach(function (s) {
            var key = s.account.key
            var existing = _accs[key]
            if (existing && existing.session === s.session) {
                next[key] = existing
                return
            }
            var a = { account: s.account, provider: s.provider, session: s.session,
                      state: s.session.createState(), syncing: false, lastSync: null, loaded: false, error: null }
            next[key] = a
            fresh.push(key)
        })
        Object.keys(_accs).forEach(function (key) {
            if (!next[key] && cache)
                cache.remove(key)
        })
        _accs = next
        _rebuild()
        _updateStatus()
        // Each new account first shows its cached snapshot (read asynchronously), then syncs from it.
        fresh.forEach(function (key) { _restoreThenRefresh(key) })
    }

    function _restoreThenRefresh(key) {
        var a = _accs[key]
        if (!a)
            return
        var loading = cache ? cache.load(key) : Promise.resolve("")
        // For a persistent provider the stored state is the data: when it cannot be read the account is
        // locked (no edits, no sync) so that an empty state never overwrites it.
        var persistent = !!a.provider.capabilities.persistent
        function broken(e) {
            console.warn("Keeplet: stored data of", key, "is unreadable:", e)
            a.broken = true
            a.error = { kind: "storage", detail: "" }
            _updateStatus()
        }
        loading.then(function (json) {
            // The account may have been removed or replaced while the cache was read.
            if (_accs[key] !== a)
                return
            if (json && !a.loaded && _pendingOf(a) === 0) {
                try {
                    var restored = a.session.restoreState(JSON.parse(json))
                    if (restored) {
                        a.state = restored
                        a.loaded = true
                        _rebuild()
                        _updateStatus()
                    } else if (persistent) {
                        broken("unrecognized format")
                    }
                } catch (e) {
                    if (persistent)
                        broken(e)
                    else
                        console.warn("Keeplet: ignoring corrupt cache for", key, e)
                }
            }
        }, function (e) {
            if (persistent)
                broken(e)
            else
                console.warn("Keeplet: cache read failed for", key, e)
        }).then(function () {
            if (_accs[key] === a)
                _refreshAccount(key)
        })
    }

    on_SessionsChanged: _adoptSessions()
    onSearchTextChanged: _applyFilter()
    onSelectedChanged: _applyFilter()
    onAccountFilterChanged: _applyFilter()
    onCurrentNoteKeyChanged: _syncCurrentNote()

    Component.onCompleted: _adoptSessions()
}
