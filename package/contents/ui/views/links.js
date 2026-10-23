.pragma library

// Links in plain note text: web addresses (with a scheme or starting with "www.") and e-mail addresses.

var PATTERN = /\b(?:(?:https?|ftp):\/\/|www\.)[^\s<>"]+|\bmailto:[^\s<>"]+|[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}/gi

function count(s, ch) {
    return s.split(ch).length - 1
}

// Punctuation that ends a sentence is not part of the link; a closing bracket is only when it has no pair inside.
function trimEnd(s) {
    for (;;) {
        var last = s.charAt(s.length - 1)
        if (".,;:!?'\"*".indexOf(last) >= 0
                || last === ")" && count(s, ")") > count(s, "(")
                || last === "]" && count(s, "]") > count(s, "["))
            s = s.substr(0, s.length - 1)
        else
            return s
    }
}

function hrefOf(s) {
    if (/^www\./i.test(s))
        return "https://" + s
    if (s.indexOf("://") < 0 && !/^mailto:/i.test(s))
        return "mailto:" + s
    return s
}

// [{start, end, text, url}] in the order they appear.
function find(text) {
    var res = []
    if (!text)
        return res
    PATTERN.lastIndex = 0
    var m
    while ((m = PATTERN.exec(text)) !== null) {
        var s = trimEnd(m[0])
        if (s === "" || /^(?:https?|ftp):\/\/$/i.test(s) || /^www\.$/i.test(s))
            continue
        res.push({ start: m.index, end: m.index + s.length, text: s, url: hrefOf(s) })
    }
    return res
}

// What "Copy link address" puts on the clipboard: the URL, or the bare address of an e-mail.
function address(url) {
    return url.replace(/^mailto:/i, "")
}

function escape(s) {
    return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;")
}

// Plain text as Text.StyledText with the links made clickable (Text.linkAt finds them).
function toStyledText(text) {
    var out = "", at = 0
    find(text).forEach(function (l) {
        out += escape(text.substring(at, l.start)) + '<a href="' + escape(l.url) + '">' + escape(l.text) + "</a>"
        at = l.end
    })
    out += escape(text.substring(at))
    // Styled text collapses white space like HTML does.
    return out.replace(/\n/g, "<br>").replace(/ {2}/g, " &nbsp;")
}
