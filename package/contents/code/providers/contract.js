.pragma library

// Structural check of the provider contract (docs/providers.md). Returns a list of problems;
// an empty list means the provider is usable. Run by tests for every provider.

var CAPABILITY_KEYS = ["labels", "colors", "checklists", "nestedItems", "convertType", "pinned", "archive", "trash", "images", "write", "reorder", "offlineEdit"]
var LABEL_MODES = ["multi", "single", "none"]
var SESSION_METHODS = ["createState", "restoreState", "sync", "notes", "labels"]
// Required when capabilities.write is true.
var WRITE_METHODS = ["commit", "remove", "pending"]
// Required when capabilities.reorder is true.
var REORDER_METHODS = ["reorder"]

function validate(provider) {
    var problems = []
    function need(cond, text) { if (!cond) problems.push(text) }

    need(provider && typeof provider.id === "string" && provider.id !== "", "id must be a non-empty string")
    need(provider && typeof provider.name === "string" && provider.name !== "", "name must be a non-empty string")
    need(provider && typeof provider.icon === "string" && provider.icon !== "", "icon must be a non-empty string")
    if (!provider)
        return problems

    var caps = provider.capabilities
    need(caps && typeof caps === "object", "capabilities must be an object")
    if (caps) {
        CAPABILITY_KEYS.forEach(function (k) { need(k in caps, "capabilities." + k + " is missing") })
        need(LABEL_MODES.indexOf(caps.labels) >= 0, "capabilities.labels must be one of " + LABEL_MODES.join("|"))
        need(Array.isArray(caps.colors), "capabilities.colors must be an array of color names (empty = unsupported)")
    }

    var fields = provider.credentialFields
    need(Array.isArray(fields) && fields.length > 0, "credentialFields must be a non-empty array")
    ;(fields || []).forEach(function (f, i) {
        need(f && typeof f.key === "string" && typeof f.label === "string", "credentialFields[" + i + "] needs key and label")
    })

    need(typeof provider.signIn === "function", "signIn must be a function")
    need(typeof provider.createSession === "function", "createSession must be a function")
    return problems
}

// `capabilities` (optional) decides whether the write methods are required.
function validateSession(session, capabilities) {
    var problems = []
    var required = SESSION_METHODS.slice()
    if (capabilities && capabilities.write)
        required = required.concat(WRITE_METHODS)
    if (capabilities && capabilities.reorder)
        required = required.concat(REORDER_METHODS)
    required.forEach(function (m) {
        if (!session || typeof session[m] !== "function")
            problems.push("session." + m + " must be a function")
    })
    return problems
}
