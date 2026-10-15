.pragma library
.import "keep/index.js" as Keep

// Providers available in the release build. Add new providers here (docs/providers.md).
var _providers = [Keep]

function list() {
    return _providers.slice()
}

function get(id) {
    for (var i = 0; i < _providers.length; i++) {
        if (_providers[i].id === id)
            return _providers[i]
    }
    return null
}
