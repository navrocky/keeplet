.pragma library

// Parses gpsoauth-style "key=value" line responses.
function parseKeyValue(text) {
    var res = {}
    text.split("\n").forEach(function (line) {
        var i = line.indexOf("=")
        if (i > 0)
            res[line.substr(0, i)] = line.substr(i + 1)
    })
    return res
}

// Encodes an object as application/x-www-form-urlencoded.
function formEncode(data) {
    return Object.keys(data).map(function (k) {
        return encodeURIComponent(k) + "=" + encodeURIComponent(data[k])
    }).join("&")
}
