.pragma library

// Model layer: Keep node graph. Pure JS, no UI or network.
// Port of the relevant parts of gkeepapi (https://github.com/kiwiz/gkeepapi, MIT). See docs/keep-protocol.md.
//
// State is plain data so it can be cached as JSON:
//   { version: "<toVersion>", nodes: { <id>: <raw server node> }, labels: { <mainId>: <raw label> } }
// Raw server nodes are kept untouched so that changed nodes can be sent back with every
// field the server gave us, including ones we don't understand.

var ROOT = "root"
var NEVER_PREFIX = "1970-01-01"

var COLORS = ["DEFAULT", "RED", "ORANGE", "YELLOW", "GREEN", "TEAL", "BLUE",
              "CERULEAN", "PURPLE", "PINK", "BROWN", "GRAY"]

function createState() {
    return { version: "", nodes: {}, labels: {} }
}

// Timestamps that were never set are serialized as the Unix epoch.
function isSet(timestamp) {
    return !!timestamp && timestamp.indexOf(NEVER_PREFIX) !== 0
}

function isDeleted(raw) {
    return !!raw.timestamps && isSet(raw.timestamps.deleted)
}

// Merges a /changes response into state (mutates it). Deleted nodes and labels are dropped.
function applyChanges(state, response) {
    ;(response.nodes || []).forEach(function (raw) {
        if (isDeleted(raw))
            delete state.nodes[raw.id]
        else
            state.nodes[raw.id] = raw
    })
    var labels = (response.userInfo && response.userInfo.labels) || []
    labels.forEach(function (label) {
        if (isDeleted(label))
            delete state.labels[label.mainId]
        else
            state.labels[label.mainId] = label
    })
    if (response.toVersion)
        state.version = response.toVersion
    return state
}

function _sortValue(raw) {
    var v = Number(raw.sortValue)
    return isNaN(v) ? 0 : v
}

// Keep shows items by descending sortValue.
function _bySortDesc(a, b) {
    return _sortValue(b) - _sortValue(a)
}

function _childrenIndex(state) {
    var index = {}
    Object.keys(state.nodes).forEach(function (id) {
        var raw = state.nodes[id]
        var parent = raw.parentId
        if (!parent)
            return
        ;(index[parent] = index[parent] || []).push(raw)
    })
    return index
}

function _labelsOf(raw, state) {
    var out = []
    ;(raw.labelIds || []).forEach(function (ref) {
        var label = state.labels[ref.labelId]
        if (label && !ref.deleted)
            out.push({ id: label.mainId, name: label.name })
    })
    return out
}

// Checklist items in display order: each top-level item followed by its sub-items.
function _listItems(children) {
    var all = children.filter(function (n) { return n.type === "LIST_ITEM" })
    var byParent = {}
    var top = []
    all.forEach(function (n) {
        if (n.superListItemId)
            (byParent[n.superListItemId] = byParent[n.superListItemId] || []).push(n)
        else
            top.push(n)
    })
    var out = []
    function push(n, indent) {
        out.push({ id: n.id, text: n.text || "", checked: !!n.checked, indent: indent })
    }
    top.sort(_bySortDesc).forEach(function (n) {
        push(n, 0)
        ;(byParent[n.id] || []).sort(_bySortDesc).forEach(function (c) { push(c, 1) })
    })
    return out
}

function _images(children) {
    return children.filter(function (n) {
        return n.type === "BLOB" && n.blob && n.blob.type === "IMAGE"
    }).map(function (n) {
        return { id: n.id, serverId: n.serverId, mimeType: n.blob.mimetype || "" }
    })
}

function _buildNote(raw, children, state) {
    var kids = children[raw.id] || []
    var isList = raw.type === "LIST"
    var items = isList ? _listItems(kids) : []
    var text = ""
    if (!isList) {
        // A text note keeps its body in a single child LIST_ITEM.
        var body = kids.filter(function (n) { return n.type === "LIST_ITEM" }).sort(_bySortDesc)[0]
        text = body ? (body.text || "") : ""
    }
    var ts = raw.timestamps || {}
    return {
        id: raw.id,
        type: raw.type,
        title: raw.title || "",
        text: text,
        items: items,
        images: _images(kids),
        color: COLORS.indexOf(raw.color) >= 0 ? raw.color : "DEFAULT",
        pinned: !!raw.isPinned,
        archived: !!raw.isArchived,
        trashed: isSet(ts.trashed),
        labels: _labelsOf(raw, state),
        sortValue: _sortValue(raw),
        created: ts.created || "",
        updated: ts.updated || ""
    }
}

// Top-level notes in Keep's order (descending sortValue). Filtering is the ViewModel's job.
function buildNotes(state) {
    var children = _childrenIndex(state)
    return (children[ROOT] || []).filter(function (raw) {
        return raw.type === "NOTE" || raw.type === "LIST"
    }).sort(_bySortDesc).map(function (raw) {
        return _buildNote(raw, children, state)
    })
}

function buildLabels(state) {
    return Object.keys(state.labels).map(function (id) {
        return { id: id, name: state.labels[id].name }
    }).sort(function (a, b) { return a.name.localeCompare(b.name) })
}
