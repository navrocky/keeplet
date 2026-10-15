.pragma library

// Aggregation of notes from several accounts. Pure functions, no UI.

var KEY_SEPARATOR = "|"

function labelKey(accountKey, labelId) {
    return accountKey + KEY_SEPARATOR + labelId
}

function noteKey(accountKey, noteId) {
    return accountKey + "/" + noteId
}

// Tags one account's notes and labels with the account so they stay distinguishable after merging.
function annotate(account, notes, labels) {
    var key = account.key
    var outLabels = labels.map(function (l) {
        return { id: l.id, name: l.name, accountKey: key, providerId: account.providerId, key: labelKey(key, l.id) }
    })
    var outNotes = notes.map(function (n) {
        var copy = {}
        for (var k in n)
            copy[k] = n[k]
        copy.accountKey = key
        copy.providerId = account.providerId
        copy.key = noteKey(key, n.id)
        copy.labels = (n.labels || []).map(function (l) {
            return { id: l.id, name: l.name, key: labelKey(key, l.id), accountKey: key }
        })
        return copy
    })
    return { notes: outNotes, labels: outLabels }
}

function merge(parts) {
    var notes = []
    var labels = []
    parts.forEach(function (p) {
        notes = notes.concat(p.notes)
        labels = labels.concat(p.labels)
    })
    return { notes: notes, labels: labels }
}

function _matches(note, query) {
    var hay = [note.title, note.text]
    note.items.forEach(function (i) { hay.push(i.text) })
    note.labels.forEach(function (l) { hay.push(l.name) })
    return hay.join("\n").toLowerCase().indexOf(query) >= 0
}

function _byOrder(a, b) { return b.order - a.order }
function _byUpdated(a, b) { return a.updated < b.updated ? 1 : (a.updated > b.updated ? -1 : 0) }

// opts: {accountFilter: "" | accountKey, view: "notes"|"archive"|"trash", labelKey: "", unlabeled: bool,
//        query: "", accountCount: n}
// Order: pinned first; within an account provider's own order, across accounts most recently updated first.
function visibleNotes(all, opts) {
    var query = (opts.query || "").trim().toLowerCase()
    var view = opts.view || "notes"
    var out = all.filter(function (n) {
        if (opts.accountFilter && n.accountKey !== opts.accountFilter)
            return false
        if (view === "trash") {
            if (!n.trashed)
                return false
        } else if (n.trashed || n.archived !== (view === "archive")) {
            return false
        }
        if (opts.labelKey && !n.labels.some(function (l) { return l.key === opts.labelKey }))
            return false
        if (opts.unlabeled && n.labels.length > 0)
            return false
        return !query || _matches(n, query)
    })
    var single = !!opts.accountFilter || (opts.accountCount || 0) <= 1
    out.sort(single ? _byOrder : _byUpdated)
    return out.filter(function (n) { return n.pinned })
              .concat(out.filter(function (n) { return !n.pinned }))
}
