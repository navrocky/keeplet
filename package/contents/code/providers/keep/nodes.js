.pragma library

// Model layer: Keep node graph. Pure JS, no UI or network.
// Port of the relevant parts of gkeepapi (https://github.com/kiwiz/gkeepapi, MIT). See docs/keep-protocol.md.
//
// State is plain data so it can be cached as JSON:
//   { version: "<toVersion>", nodes: { <id>: <raw server node> }, labels: { <mainId>: <raw label> },
//     dirty: { <id>: {node, rev} }, labelsDirty: { <mainId>: {label, rev} }, rev: <counter> }
// Raw server nodes are kept untouched so that changed nodes can be sent back with every
// field the server gave us, including ones we don't understand.
// `dirty` holds local edits not yet accepted by the server: the node to send and the revision at which
// it was last edited. `labelsDirty` is the same for labels (created, renamed or deleted here; a deleted label
// is only kept there, not in `labels`). Edits survive restarts because the whole state is cached.

var ROOT = "root"
var NEVER_PREFIX = "1970-01-01"

var COLORS = ["DEFAULT", "RED", "ORANGE", "YELLOW", "GREEN", "TEAL", "BLUE",
              "CERULEAN", "PURPLE", "PINK", "BROWN", "GRAY"]

function createState() {
    return { version: "", nodes: {}, labels: {}, dirty: {}, labelsDirty: {}, rev: 0 }
}

// A cached state from an older layout (no `dirty`) is upgraded in place.
function normalizeState(state) {
    if (!state.dirty || typeof state.dirty !== "object")
        state.dirty = {}
    if (!state.labelsDirty || typeof state.labelsDirty !== "object")
        state.labelsDirty = {}
    if (typeof state.rev !== "number")
        state.rev = 0
    return state
}

// Records a locally changed raw node: visible immediately, queued for the next sync.
function markDirty(state, raw) {
    state.nodes[raw.id] = raw
    state.rev += 1
    state.dirty[raw.id] = { node: raw, rev: state.rev }
}

// Records a locally created, renamed or deleted raw label (a deleted one has timestamps.deleted set).
function markLabelDirty(state, raw) {
    if (isDeleted(raw))
        delete state.labels[raw.mainId]
    else
        state.labels[raw.mainId] = raw
    state.rev += 1
    state.labelsDirty[raw.mainId] = { label: raw, rev: state.rev }
}

// Local edits (notes and labels) not yet accepted by the server.
function pendingCount(state) {
    return Object.keys(state.dirty || {}).length + Object.keys(state.labelsDirty || {}).length
}

// Timestamps that were never set are serialized as the Unix epoch.
function isSet(timestamp) {
    return !!timestamp && timestamp.indexOf(NEVER_PREFIX) !== 0
}

function isDeleted(raw) {
    return !!raw.timestamps && isSet(raw.timestamps.deleted)
}

// Merges a /changes response into state (mutates it). Deleted nodes and labels are dropped.
// options.skip(id) -> true keeps the local version of that node (an edit made while the request
// was in flight must not be overwritten by the older server copy); options.skipLabel(mainId) does the same
// for a label.
//
// userInfo.labels, when present, is the COMPLETE list of the account's labels (verified: a deleted label is
// simply absent, there is no tombstone), so labels missing from it are dropped. A response without
// userInfo leaves the labels alone.
function applyChanges(state, response, options) {
    var skip = options && options.skip
    ;(response.nodes || []).forEach(function (raw) {
        if (skip && skip(raw.id))
            return
        if (isDeleted(raw))
            delete state.nodes[raw.id]
        else
            state.nodes[raw.id] = raw
    })
    var serverLabels = response.userInfo && response.userInfo.labels
    if (Array.isArray(serverLabels)) {
        var skipLabel = options && options.skipLabel
        var next = {}
        serverLabels.forEach(function (label) {
            if (isDeleted(label) || (skipLabel && skipLabel(label.mainId)))
                return
            next[label.mainId] = label
        })
        // A label edited while the request was in flight keeps its newer local version.
        if (skipLabel) {
            Object.keys(state.labels).forEach(function (id) {
                if (skipLabel(id))
                    next[id] = state.labels[id]
            })
        }
        state.labels = next
    }
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
        // Locally deleted nodes disappear at once, before the server confirms.
        if (!parent || isDeleted(raw))
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

// One top-level note by id (any state: archived, trashed), or null.
function buildNote(state, id) {
    var raw = state.nodes[id]
    if (!raw || raw.parentId !== ROOT || isDeleted(raw) || (raw.type !== "NOTE" && raw.type !== "LIST"))
        return null
    // Only this note's children (one pass over the nodes), not the whole account.
    var kids = []
    Object.keys(state.nodes).forEach(function (nodeId) {
        var n = state.nodes[nodeId]
        if (n.parentId === id && !isDeleted(n))
            kids.push(n)
    })
    var children = {}
    children[id] = kids
    return _buildNote(raw, children, state)
}

function buildLabels(state) {
    return Object.keys(state.labels).map(function (id) {
        return { id: id, name: state.labels[id].name }
    }).sort(function (a, b) { return a.name.localeCompare(b.name) })
}
