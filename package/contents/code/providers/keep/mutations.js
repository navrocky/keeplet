.pragma library
.import "nodes.js" as Nodes

// Turns an edited note (provider-neutral snapshot, see core/notes.js) into the raw Keep nodes that must be
// sent. Pure functions over the provider state: no network, no UI. Shapes follow gkeepapi's Node.save() and
// were verified against a real account (docs/keep-protocol.md, "Writing").
//
// Snapshot: {id, type, title, text, items: [{id, text, checked, indent}], color, pinned, archived,
//            trashed, labels: [{id, name}]}. Ids of new notes/items may be empty: they are generated.

var NEVER = "1970-01-01T00:00:00.000000Z"
var STEP = 1000000          // distance between neighbouring sort values we assign
var BASE_SORT = 2000000000  // first sort value in an empty list; items are shown by descending value

function defaultContext() {
    return {
        now: function () { return new Date().toISOString().replace("Z", "000Z") },
        newId: function () { return Date.now().toString(16) + "." + _hex(16) }
    }
}

function _hex(n) {
    var s = ""
    for (var i = 0; i < n; i++)
        s += Math.floor(Math.random() * 16).toString(16)
    return s
}

function _clone(o) { return JSON.parse(JSON.stringify(o)) }
function _num(v) { var n = Number(v); return isNaN(n) ? 0 : n }
function _bySortDesc(a, b) { return _num(b.sortValue) - _num(a.sortValue) }

function _stamps(now) {
    return { kind: "notes#timestamps", created: now, updated: now, trashed: NEVER, deleted: NEVER, userEdited: now }
}

function _children(state, parentId) {
    return Object.keys(state.nodes).map(function (id) { return state.nodes[id] }).filter(function (n) {
        return n.parentId === parentId && !Nodes.isDeleted(n)
    })
}

function _items(state, noteId) {
    return _children(state, noteId).filter(function (n) { return n.type === "LIST_ITEM" }).sort(_bySortDesc)
}

function _newItem(parentId, item, sort, superId, ctx, now) {
    var node = {
        id: item.id || ctx.newId(), kind: "notes#node", type: "LIST_ITEM", parentId: parentId,
        sortValue: String(sort), text: item.text || "", checked: !!item.checked, timestamps: _stamps(now)
    }
    if (superId)
        node.superListItemId = superId
    return node
}

// Sort values for items in display order. `known` holds the existing value or null for new items.
function _assignSorts(known) {
    var out = known.slice()
    for (var i = 0; i < out.length; i++) {
        if (out[i] !== null)
            continue
        var above = i > 0 ? out[i - 1] : null
        var below = null
        for (var j = i + 1; j < known.length; j++) {
            if (known[j] !== null) {
                below = known[j]
                break
            }
        }
        if (above !== null) {
            var candidate = above - STEP
            if (below !== null && candidate <= below)
                candidate = Math.floor((above + below) / 2)
            out[i] = candidate
        } else if (below !== null) {
            out[i] = below + STEP
        } else {
            out[i] = BASE_SORT - i * STEP
        }
    }
    return out
}

function _topSort(state) {
    var max = null
    _children(state, "root").forEach(function (n) {
        var v = _num(n.sortValue)
        if (max === null || v > max)
            max = v
    })
    return max === null ? BASE_SORT : max + STEP
}

function _parents(items) {
    // Indented items hang under the closest item above with indent 0.
    var lastTop = ""
    return items.map(function (it) {
        var parent = it.indent > 0 ? lastTop : ""
        if (!(it.indent > 0))
            lastTop = it.id
        return parent
    })
}

// Creates a note. Returns {id, nodes}. Does not touch the state.
function createNote(state, snap, ctx) {
    ctx = ctx || defaultContext()
    var now = ctx.now()
    var id = snap.id || ctx.newId()
    var top = {
        id: id, kind: "notes#node", type: snap.type === "LIST" ? "LIST" : "NOTE", parentId: "root",
        sortValue: String(_topSort(state)), title: snap.title || "", color: snap.color || "DEFAULT",
        isArchived: !!snap.archived, isPinned: !!snap.pinned,
        labelIds: (snap.labels || []).map(function (l) { return { labelId: l.id, deleted: NEVER } }),
        timestamps: _stamps(now),
        nodeSettings: { newListItemPlacement: "BOTTOM", checkedListItemPolicy: "GRAVEYARD", graveyardState: "EXPANDED" },
        annotationsGroup: { kind: "notes#annotationsGroup" }
    }
    if (snap.trashed)
        top.timestamps.trashed = now
    var nodes = [top]
    if (top.type === "NOTE") {
        nodes.push(_newItem(id, { text: snap.text || "" }, BASE_SORT, "", ctx, now))
    } else {
        var items = (snap.items || []).map(function (it) {
            return { id: it.id || ctx.newId(), text: it.text, checked: it.checked, indent: it.indent || 0 }
        })
        var parents = _parents(items)
        var sorts = _assignSorts(items.map(function () { return null }))
        items.forEach(function (it, i) { nodes.push(_newItem(id, it, sorts[i], parents[i], ctx, now)) })
    }
    return { id: id, nodes: nodes }
}

// Compares `snap` with the note in the state and returns the changed raw nodes (deep copies, with
// timestamps updated). An unknown id creates the note. Returns {id, nodes}; nodes is empty when nothing changed.
function commitNote(state, snap, ctx) {
    ctx = ctx || defaultContext()
    var raw = snap.id ? state.nodes[snap.id] : null
    if (!raw || Nodes.isDeleted(raw))
        return createNote(state, snap, ctx)

    var now = ctx.now()
    var out = []
    var top = _clone(raw)
    var topChanged = false
    var contentChanged = false // title, text or items: also bumps userEdited, like the apps do

    function setTop(changed, content) {
        if (changed) {
            topChanged = true
            if (content)
                contentChanged = true
        }
    }

    if ((top.title || "") !== (snap.title || "")) {
        top.title = snap.title || ""
        setTop(true, true)
    }
    if ((top.color || "DEFAULT") !== (snap.color || "DEFAULT")) {
        top.color = snap.color || "DEFAULT"
        setTop(true, false)
    }
    if (!!top.isPinned !== !!snap.pinned) {
        top.isPinned = !!snap.pinned
        setTop(true, false)
    }
    if (!!top.isArchived !== !!snap.archived) {
        top.isArchived = !!snap.archived
        setTop(true, false)
    }
    var wasTrashed = Nodes.isSet(top.timestamps && top.timestamps.trashed)
    if (wasTrashed !== !!snap.trashed) {
        top.timestamps.trashed = snap.trashed ? now : NEVER
        setTop(true, false)
    }

    // Labels: add missing, mark removed ones as deleted (the server then drops the entry).
    var wanted = {}
    ;(snap.labels || []).forEach(function (l) { wanted[l.id] = true })
    var labelIds = top.labelIds || []
    var present = {}
    labelIds.forEach(function (l) {
        if (Nodes.isSet(l.deleted))
            return
        present[l.labelId] = true
        if (!wanted[l.labelId]) {
            l.deleted = now
            setTop(true, false)
        }
    })
    Object.keys(wanted).forEach(function (id) {
        if (!present[id]) {
            labelIds.push({ labelId: id, deleted: NEVER })
            setTop(true, false)
        }
    })
    top.labelIds = labelIds

    var children = []

    if (raw.type === "LIST") {
        var existing = _items(state, snap.id)
        var wantedIds = {}
        ;(snap.items || []).forEach(function (it) { if (it.id) wantedIds[it.id] = true })

        existing.forEach(function (n) {
            if (!wantedIds[n.id]) {
                var gone = _clone(n)
                gone.timestamps.deleted = now
                gone.timestamps.updated = now
                children.push(gone)
                contentChanged = true
                topChanged = true
            }
        })

        var items = (snap.items || []).map(function (it) {
            return { id: it.id || ctx.newId(), text: it.text, checked: it.checked, indent: it.indent || 0, isNew: !it.id || !state.nodes[it.id] }
        })
        var parents = _parents(items)
        var sorts = _assignSorts(items.map(function (it) {
            return it.isNew ? null : _num(state.nodes[it.id].sortValue)
        }))

        items.forEach(function (it, i) {
            if (it.isNew) {
                children.push(_newItem(snap.id, it, sorts[i], parents[i], ctx, now))
                contentChanged = true
                topChanged = true
                return
            }
            var c = _clone(state.nodes[it.id])
            var changed = false
            if ((c.text || "") !== (it.text || "")) {
                c.text = it.text || ""
                changed = true
                contentChanged = true
            }
            if (!!c.checked !== !!it.checked) {
                c.checked = !!it.checked
                changed = true
            }
            if ((c.superListItemId || "") !== parents[i]) {
                if (parents[i])
                    c.superListItemId = parents[i]
                else
                    delete c.superListItemId
                delete c.superListItemServerId
                changed = true
            }
            if (changed) {
                c.timestamps.updated = now
                children.push(c)
                topChanged = true
            }
        })
    } else {
        var body = _items(state, snap.id)[0]
        var text = snap.text || ""
        if (body) {
            if ((body.text || "") !== text) {
                var b = _clone(body)
                b.text = text
                b.timestamps.updated = now
                children.push(b)
                contentChanged = true
                topChanged = true
            }
        } else if (text !== "") {
            children.push(_newItem(snap.id, { text: text }, BASE_SORT, "", ctx, now))
            contentChanged = true
            topChanged = true
        }
    }

    if (topChanged) {
        top.timestamps.updated = now
        if (contentChanged)
            top.timestamps.userEdited = now
        out.push(top)
    }
    return { id: snap.id, nodes: out.concat(children) }
}

// Nodes that delete a note for good: the note and all its items.
function deleteNote(state, noteId, ctx) {
    ctx = ctx || defaultContext()
    var now = ctx.now()
    var raws = [state.nodes[noteId]].concat(_children(state, noteId)).filter(function (n) { return !!n })
    return raws.map(function (n) {
        var c = _clone(n)
        c.timestamps.deleted = now
        c.timestamps.updated = now
        return c
    })
}

// Applies a snapshot to the state: the edit is visible at once and queued for the next sync.
// Returns the id of the note (new notes get their id here).
function commit(state, snap, ctx) {
    var result = commitNote(state, snap, ctx)
    result.nodes.forEach(function (n) { Nodes.markDirty(state, n) })
    return result.id
}

function remove(state, noteId, ctx) {
    deleteNote(state, noteId, ctx).forEach(function (n) { Nodes.markDirty(state, n) })
}
