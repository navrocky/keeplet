// Stage C0 spike: what does the Keep private API need and return when WRITING?
// Creates two throwaway notes ("keeplet write test ...") in the signed-in account, edits them
// step by step, then trashes and deletes them. It never modifies a node it did not create.
// Run via spike/run-write.sh. Output contains no tokens.
import QtQuick
import "../package/contents/code/providers/keep/gauth.js" as GAuth
import "../package/contents/code/providers/keep/keepapi.js" as KeepApi
import "../package/contents/code/providers/keep/nodes.js" as Nodes

Item {
    readonly property string never: "1970-01-01T00:00:00.000000Z"

    // qml6 spike/write.qml -- <state.json> <run|dry>
    readonly property var args: Qt.application.arguments
    readonly property string statePath: args[args.length - 2]
    readonly property bool dry: args[args.length - 1] === "dry"
    readonly property string tag: "keeplet write test"

    property var st: ({})
    property var state: Nodes.createState()
    property string sessionId: KeepApi.newSessionId()
    property var created: []      // ids of nodes this run created
    property var createdLabels: [] // mainIds of labels this run created (only these are ever edited or deleted)
    property string authValue: "" // never printed

    function log(s) { console.log(s) }
    function readFile(path) {
        var x = new XMLHttpRequest()
        x.open("GET", "file://" + path, false)
        x.send()
        return x.responseText
    }
    function hex(n) {
        var s = ""
        for (var i = 0; i < n; i++) s += Math.floor(Math.random() * 16).toString(16)
        return s
    }
    function now() { return KeepApi.timestamp() }
    function genId() { return Date.now().toString(16) + "." + hex(16) }
    function sortValue() { return String(1000000000 + Math.floor(Math.random() * 8999999999)) }
    function stamps() {
        var n = now()
        return { kind: "notes#timestamps", created: n, updated: n, trashed: never, deleted: never, userEdited: n }
    }

    // --- node builders (shapes follow gkeepapi's Node.save())
    function newNote(type, title) {
        var id = genId()
        created.push(id)
        return {
            id: id, kind: "notes#node", type: type, parentId: "root", sortValue: sortValue(),
            title: title, color: "DEFAULT", isArchived: false, isPinned: false, labelIds: [],
            timestamps: stamps(),
            nodeSettings: { newListItemPlacement: "BOTTOM", checkedListItemPolicy: "GRAVEYARD", graveyardState: "EXPANDED" },
            annotationsGroup: { kind: "notes#annotationsGroup" }
        }
    }
    function newItem(parentId, text, checked) {
        var id = genId()
        created.push(id)
        return {
            id: id, kind: "notes#node", type: "LIST_ITEM", parentId: parentId, sortValue: sortValue(),
            text: text, checked: !!checked, timestamps: stamps()
        }
    }
    // A changed copy of a node the server already knows (keeps serverId, baseVersion, unknown fields).
    function edit(id, fn) {
        var raw = state.nodes[id]
        if (!raw)
            throw new Error("node " + id + " is not in the local state")
        var copy = JSON.parse(JSON.stringify(raw))
        fn(copy)
        copy.timestamps.updated = now()
        return copy
    }

    // --- transport
    function authToken() {
        if (authValue)
            return Promise.resolve(authValue)
        return GAuth.performOAuth(st.email, st.master_token, st.android_id).then(function (r) {
            authValue = r.token
            return authValue
        })
    }

    function describe(n) {
        return n.id + " type=" + n.type + " serverId=" + n.serverId + " baseVersion=" + n.baseVersion
    }

    function report(label, sent, resp) {
        log("")
        log("== " + label)
        log("   response keys: " + Object.keys(resp).join(","))
        log("   nodes returned: " + (resp.nodes || []).length + "  truncated=" + !!resp.truncated
            + "  forceFullResync=" + !!resp.forceFullResync)
        sent.forEach(function (s) {
            var r = (resp.nodes || []).filter(function (n) { return n.id === s.id })[0]
            if (!r) {
                log("   " + s.id + " (" + s.type + "): NOT in the response")
                return
            }
            var diffs = []
            ;["title", "text", "color", "isPinned", "isArchived", "checked", "parentId", "sortValue"].forEach(function (k) {
                if (k in s && JSON.stringify(s[k]) !== JSON.stringify(r[k]))
                    diffs.push(k + ": sent=" + JSON.stringify(s[k]) + " got=" + JSON.stringify(r[k]))
            })
            log("   " + describe(r) + (diffs.length ? "   DIFFERENCES: " + diffs.join("; ") : "   (echo matches)"))
            log("     fields added by server: " + (Object.keys(r).filter(function (k) { return !(k in s) }).join(",") || "-"))
            log("     timestamps: " + JSON.stringify(r.timestamps))
            if (r.labelIds && r.labelIds.length)
                log("     labelIds: " + JSON.stringify(r.labelIds))
        })
    }

    // Sends `nodes` in one /changes request, prints what came back, merges it into the state.
    function push(label, nodes) {
        return authToken().then(function (token) {
            var body = KeepApi.buildRequest(state, nodes, sessionId)
            return KeepApi.changes(token, body).then(function (resp) {
                report(label, nodes, resp)
                Nodes.applyChanges(state, resp)
                // Drain further pages if the server splits the reply.
                return resp.truncated ? KeepApi.sync(token, state, [], undefined) : state
            })
        })
    }

    // A label as gkeepapi's Label.save() builds it.
    function newLabel(name) {
        var id = genId()
        createdLabels.push(id)
        return { mainId: id, name: name, timestamps: stamps(), lastMerged: now() }
    }
    function labelCopy(id, fn) {
        var raw = state.labels[id]
        if (!raw)
            throw new Error("label " + id + " is not in the local state (server did not echo it?)")
        var copy = JSON.parse(JSON.stringify(raw))
        fn(copy)
        copy.timestamps.updated = now()
        copy.lastMerged = now()
        return copy
    }
    function noteLabelIds(id) {
        var n = state.nodes[id]
        return n ? JSON.stringify(n.labelIds || []) : "(note not in state)"
    }

    // Sends labels (userInfo.labels) and optionally nodes in one /changes request and prints the echoes.
    function pushLabels(label, labels, nodes) {
        return authToken().then(function (token) {
            var body = KeepApi.buildRequest(state, nodes || [], sessionId)
            body.userInfo = { labels: labels }
            log("")
            log("   request userInfo.labels: " + JSON.stringify(labels))
            return KeepApi.changes(token, body).then(function (resp) {
                report(label, nodes || [], resp)
                var echoed = (resp.userInfo && resp.userInfo.labels) || []
                log("   response userInfo.labels (" + echoed.length + "): " + JSON.stringify(echoed))
                log("   response userInfo keys: " + Object.keys(resp.userInfo || {}).join(",") + "  top-level keys: " + Object.keys(resp).join(","))
                labels.forEach(function (l) {
                    var r = echoed.filter(function (e) { return e.mainId === l.mainId })[0]
                    log("   label " + l.mainId + " '" + l.name + "': " + (r ? "echoed as '" + r.name + "'" : "NOT echoed (mainId kept? check the list above)"))
                })
                Nodes.applyChanges(state, resp)
                return state
            })
        })
    }

    // --- scenario
    property var steps: []

    function buildSteps() {
        var note, body, list, item1, item2, item3, label
        var out = []

        out.push(["create text note", function () {
            note = newNote("NOTE", tag + " (note)")
            body = newItem(note.id, "hello from keeplet", false)
            return push("1. create text note + its body item", [note, body])
        }])
        out.push(["edit title, body, color, pin", function () {
            var n = edit(note.id, function (c) { c.title = tag + " (note, edited)"; c.color = "BLUE"; c.isPinned = true })
            var b = edit(body.id, function (c) { c.text = "hello again" })
            return push("2. edit title/color/pin on the note and text on the body item", [n, b])
        }])
        out.push(["archive and unarchive", function () {
            return push("3a. archive", [edit(note.id, function (c) { c.isArchived = true })]).then(function () {
                return push("3b. unarchive", [edit(note.id, function (c) { c.isArchived = false })])
            })
        }])
        out.push(["checklist", function () {
            list = newNote("LIST", tag + " (list)")
            item1 = newItem(list.id, "first", false)
            item2 = newItem(list.id, "second", false)
            return push("4a. create checklist with two items", [list, item1, item2]).then(function () {
                return push("4b. check the first item", [edit(item1.id, function (c) { c.checked = true })])
            }).then(function () {
                item3 = newItem(list.id, "third (added later)", false)
                return push("4c. add a third item", [item3])
            }).then(function () {
                return push("4d. indent the third item under the second",
                            [edit(item3.id, function (c) { c.superListItemId = item2.id })])
            })
        }])
        out.push(["reorder", function () {
            // Manual order: notes are shown by descending sortValue. Move the note above the list, then below it.
            var listSort = Number(state.nodes[list.id].sortValue)
            return push("4e. move the note above the list (sortValue " + (listSort + 1000000) + ")",
                        [edit(note.id, function (c) { c.sortValue = String(listSort + 1000000) })]).then(function () {
                return push("4f. move the note below the list (sortValue " + (listSort - 1000000) + ")",
                            [edit(note.id, function (c) { c.sortValue = String(listSort - 1000000) })])
            })
        }])
        out.push(["label on the test note", function () {
            var labels = Object.keys(state.labels)
            if (labels.length === 0) {
                log("")
                log("== 5. label: the account has no labels, step skipped")
                return Promise.resolve()
            }
            label = labels[0]
            log("")
            log("   (using the existing label '" + state.labels[label].name + "' on the test note only)")
            return push("5a. add a label to the test note", [edit(note.id, function (c) {
                c.labelIds = (c.labelIds || []).concat([{ labelId: label, deleted: never }])
            })]).then(function () {
                return push("5b. remove the label again", [edit(note.id, function (c) {
                    c.labelIds = (c.labelIds || []).map(function (l) {
                        return l.labelId === label ? { labelId: l.labelId, deleted: now() } : l
                    })
                })])
            })
        }])
        out.push(["labels: create, attach, rename, delete (throwaway labels only)", function () {
            var a, b
            return pushLabels("5c. create a throwaway label (userInfo.labels only)", [a = newLabel(tag + " label A")]).then(function () {
                log("   label A in local state after the response: " + (a.mainId in state.labels))
                return push("5d. attach label A to the test note", [edit(note.id, function (c) {
                    c.labelIds = (c.labelIds || []).concat([{ labelId: a.mainId, deleted: never }])
                })])
            }).then(function () {
                return pushLabels("5e. rename label A", [labelCopy(a.mainId, function (c) { c.name = tag + " label A (renamed)" })])
            }).then(function () {
                log("   test note labelIds now: " + noteLabelIds(note.id))
                b = newLabel(tag + " label B")
                return pushLabels("5f. create label B and attach it to the test note in the SAME request", [b],
                                  [edit(note.id, function (c) { c.labelIds = (c.labelIds || []).concat([{ labelId: b.mainId, deleted: never }]) })])
            }).then(function () {
                return pushLabels("5g. delete label A (timestamps.deleted = now)", [labelCopy(a.mainId, function (c) { c.timestamps.deleted = now() })])
            }).then(function () {
                log("   label A still in local state after delete: " + (a.mainId in state.labels))
                log("   test note labelIds after deleting A (does the server strip the link?): " + noteLabelIds(note.id))
                return KeepApi.sync(authValue, state, [], undefined)
            }).then(function () {
                log("   after a fresh pull: label A present: " + (a.mainId in state.labels) + "; test note labelIds: " + noteLabelIds(note.id))
                return pushLabels("5h. delete label B", [labelCopy(b.mainId, function (c) { c.timestamps.deleted = now() })])
            }).then(function () {
                log("   label B still in local state after delete: " + (b.mainId in state.labels))
            })
        }])
        out.push(["trash", function () {
            var nodes = [note, list].map(function (n) {
                return edit(n.id, function (c) { c.timestamps.trashed = now() })
            })
            return push("6. move both test notes to the trash", nodes)
        }])
        out.push(["delete", function () {
            var all = created.filter(function (id) { return id in state.nodes })
            var nodes = all.map(function (id) {
                return edit(id, function (c) { c.timestamps.deleted = now() })
            })
            return push("7. delete both test notes and their items for good", nodes)
        }])
        return out
    }

    function leftovers() {
        return created.filter(function (id) { return id in state.nodes })
    }

    function leftoverLabels() {
        return createdLabels.filter(function (id) { return id in state.labels })
    }

    function cleanup() {
        var left = leftovers()
        var leftLabels = leftoverLabels()
        if (left.length === 0 && leftLabels.length === 0)
            return Promise.resolve()
        if (left.length === 0) {
            log("")
            log("!! deleting " + leftLabels.length + " leftover test label(s)")
            return pushLabels("cleanup labels", leftLabels.map(function (id) {
                return labelCopy(id, function (c) { c.timestamps.deleted = now() })
            })).catch(function (e) {
                log("!! label cleanup failed: " + e + ". Delete labels named '" + tag + " label...' manually.")
            })
        }
        log("")
        log("!! cleaning up " + left.length + " leftover test node(s)")
        var nodes = left.map(function (id) {
            return edit(id, function (c) { c.timestamps.trashed = now(); c.timestamps.deleted = now() })
        })
        return push("cleanup", nodes).then(function () {
            return leftLabels.length === 0 ? null : pushLabels("cleanup labels", leftLabels.map(function (id) {
                return labelCopy(id, function (c) { c.timestamps.deleted = now() })
            }))
        }).catch(function (e) {
            log("!! cleanup failed: " + e + ". Delete notes titled '" + tag + "...' manually.")
        })
    }

    function finish(ok) {
        log("")
        log(ok ? "RESULT: OK. Leftover test nodes: " + leftovers().length + ", labels: " + leftoverLabels().length
               : "RESULT: FAILED. Leftover test nodes: " + leftovers().length + ", labels: " + leftoverLabels().length)
        Qt.exit(ok ? 0 : 1)
    }

    function run() {
        var all = buildSteps()
        var chain = authToken().then(function () {
            log("authorized (token not shown)")
            return KeepApi.sync(authValue, state, [], undefined)
        }).then(function () {
            log("initial pull: " + Object.keys(state.nodes).length + " nodes, "
                + Object.keys(state.labels).length + " labels, version known: " + (state.version !== ""))
        })
        all.forEach(function (s) {
            chain = chain.then(function () { return s[1]() })
        })
        chain.then(function () {
            return KeepApi.sync(authValue, state, [], undefined)
        }).then(function () {
            log("")
            log("== final pull: test nodes still present: " + leftovers().length)
            finish(leftovers().length === 0 && leftoverLabels().length === 0)
        }).catch(function (e) {
            log("")
            log("!! step failed: " + e + (e && e.kind ? " [" + e.kind + " " + e.status + "]" : ""))
            cleanup().then(function () { finish(false) })
        })
    }

    Component.onCompleted: {
        st = JSON.parse(readFile(statePath))
        if (!st.master_token) {
            log("no master token in the state file; run spike/run-auth.sh first")
            Qt.exit(2)
            return
        }
        if (dry) {
            // Show the payloads of step 1 and the plan; send nothing, not even auth.
            var note = newNote("NOTE", tag + " (note)")
            var body = newItem(note.id, "hello from keeplet", false)
            log("DRY RUN: nothing is sent. Payload of step 1 (POST /changes `nodes`):")
            log(JSON.stringify([note, body], null, 2))
            log("")
            log("Steps that would run: " + buildSteps().map(function (s, i) { return (i + 1) + ". " + s[0] }).join("; "))
            Qt.exit(0)
            return
        }
        run()
    }
}
