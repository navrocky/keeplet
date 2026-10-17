.pragma library

// Label editing on a plain container {notes: [{labels: [{id, name}]}], labels: [{id, name}]}, shared by the
// providers that keep labels as neutral data (local, fake). Names are trimmed and unique per account,
// ignoring case. Each function returns the result described in docs/providers.md or a falsy value.

function cleanName(name) {
    return String(name === undefined || name === null ? "" : name).trim().replace(/\s+/g, " ")
}

function _clash(labels, name, exceptId) {
    var lower = name.toLowerCase()
    return labels.some(function (l) { return l.id !== exceptId && l.name.toLowerCase() === lower })
}

// Whether `name` could name a label (not empty, not taken by another label).
function nameAvailable(labels, name, exceptId) {
    var n = cleanName(name)
    return n !== "" && !_clash(labels, n, exceptId)
}

function create(container, name, newId) {
    var n = cleanName(name)
    if (!nameAvailable(container.labels, n))
        return null
    var label = { id: newId(), name: n }
    container.labels.push(label)
    return { id: label.id, name: label.name }
}

function rename(container, id, name) {
    var n = cleanName(name)
    var found = null
    container.labels.forEach(function (l) { if (l.id === id) found = l })
    if (!found || !nameAvailable(container.labels, n, id))
        return false
    found.name = n
    container.notes.forEach(function (note) {
        ;(note.labels || []).forEach(function (l) { if (l.id === id) l.name = n })
    })
    return true
}

function remove(container, id) {
    var before = container.labels.length
    container.labels = container.labels.filter(function (l) { return l.id !== id })
    if (container.labels.length === before)
        return false
    container.notes.forEach(function (note) {
        note.labels = (note.labels || []).filter(function (l) { return l.id !== id })
    })
    return true
}
