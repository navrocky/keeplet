.pragma library
.import "nodes.js" as Nodes

// Model layer: Keep private API transport. No UI; the caller supplies the auth token.
// See docs/keep-protocol.md.

var BASE_URL = "https://www.googleapis.com/notes/v1/"
var CAPABILITIES = ["NC", "PI", "LB", "AN", "SH", "DR", "TR", "IN", "SNB", "MI", "CO"]
// Guard against a server that never stops saying "truncated".
var MAX_PAGES = 200

// kind: "Unauthorized" (HTTP 401: refresh the token and retry), "Network", "Http", "Protocol".
function KeepApiError(kind, status, message) {
    this.kind = kind
    this.status = status || 0
    this.message = message || (kind + (status ? " (HTTP " + status + ")" : ""))
}
KeepApiError.prototype.toString = function () { return "KeepApiError: " + this.message }

function _randomDigits(n) {
    var s = ""
    for (var i = 0; i < n; i++)
        s += Math.floor(Math.random() * 10)
    return s
}

function newSessionId() {
    return "s--" + Date.now() + "--" + _randomDigits(10)
}

// Microsecond-precision UTC timestamp as the server expects.
function timestamp(date) {
    return (date || new Date()).toISOString().replace("Z", "000Z")
}

function buildRequest(state, dirtyNodes, sessionId) {
    var req = {
        nodes: dirtyNodes || [],
        clientTimestamp: timestamp(),
        requestHeader: {
            clientSessionId: sessionId,
            clientPlatform: "ANDROID",
            clientVersion: { major: "9", minor: "9", build: "9", revision: "9" },
            capabilities: CAPABILITIES.map(function (t) { return { type: t } })
        }
    }
    if (state.version)
        req.targetVersion = state.version
    return req
}

// Resolves with parsed JSON of POST /changes.
function changes(authToken, body) {
    return new Promise(function (resolve, reject) {
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return
            if (xhr.status === 0)
                return reject(new KeepApiError("Network"))
            if (xhr.status === 401)
                return reject(new KeepApiError("Unauthorized", 401))
            if (xhr.status !== 200)
                return reject(new KeepApiError("Http", xhr.status))
            try {
                resolve(JSON.parse(xhr.responseText))
            } catch (e) {
                reject(new KeepApiError("Protocol", 200, "invalid JSON in response"))
            }
        }
        xhr.open("POST", BASE_URL + "changes")
        xhr.setRequestHeader("Authorization", "OAuth " + authToken)
        xhr.setRequestHeader("Content-Type", "application/json")
        xhr.send(JSON.stringify(body))
    })
}

// Pulls (and pushes dirtyNodes with the first page) until the server says nothing is truncated.
// Mutates state. Resolves with state. send(authToken, body) is injectable for tests.
// options.skip(id) keeps the local version of a node (see nodes.applyChanges).
// A forced full resync drops the cached server data but keeps pending local edits and sends them again.
function sync(authToken, state, dirtyNodes, send, options) {
    send = send || changes
    var applyOptions = options && options.skip ? { skip: options.skip } : undefined
    var sessionId = newSessionId()
    var pages = 0

    function step(nodes, resynced) {
        if (++pages > MAX_PAGES)
            return Promise.reject(new KeepApiError("Protocol", 0, "too many pages"))
        return send(authToken, buildRequest(state, nodes, sessionId)).then(function (resp) {
            if (resp.forceFullResync) {
                if (resynced)
                    throw new KeepApiError("Protocol", 0, "server keeps asking for a full resync")
                state.version = ""
                state.nodes = {}
                state.labels = {}
                var resend = Object.keys(state.dirty || {}).map(function (id) {
                    state.nodes[id] = state.dirty[id].node
                    return state.dirty[id].node
                })
                return step(resend, true)
            }
            Nodes.applyChanges(state, resp, applyOptions)
            if (resp.truncated)
                return step([], resynced)
            return state
        })
    }
    return step(dirtyNodes || [], false)
}
