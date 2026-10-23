.pragma library

// Links in plain note text: web addresses (with a scheme or starting with "www."), e-mail addresses and phone numbers.

// Alternatives in priority order, so at one place a web or e-mail address wins over a phone number:
// web address | mailto:/tel: | e-mail | phone candidate (digits with spaces, dashes, dots, brackets; isPhone() decides).
// (One literal: QML's RegExp.source double-escapes "\/", so the parts cannot be joined from separate literals.)
var PATTERN = /\b(?:(?:https?|ftp):\/\/|www\.)[^\s<>"]+|\b(?:mailto|tel):[^\s<>"]+|[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}|(?:\+|\(|\b)\d[\d ().-]{5,}\d/gi

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

function digitsOf(s) {
    return s.replace(/\D/g, "")
}

// Whether a candidate (see PATTERN) looks like a phone number rather than a date, an amount or an IP address.
// `before` / `after` are the characters around it in the text.
function isPhone(s, before, after) {
    if (/[A-Za-z0-9_+@]/.test(before) || /[A-Za-z0-9_@:]/.test(after))
        return false
    if (count(s, "(") !== count(s, ")"))
        return false
    if (/\d{4}[-./]\d{1,2}[-./]\d{1,2}|\d{1,2}[-./]\d{1,2}[-./]\d{4}/.test(s)  // dates
            || /^\d{1,3}(?:\.\d{1,3}){3}$/.test(s)                             // IPv4
            || /^\d{1,3}(?:[ .]\d{3})+$/.test(s))                              // thousands: 1 000 000
        return false
    var n = digitsOf(s).length
    if (n > 15)
        return false
    if (s.charAt(0) === "+")
        return n >= 7
    // Without a country code: a full number, or a short local one written in groups (123-45-67).
    return n >= 10 || n >= 7 && /\d[ ().-]+\d.*\d[ ().-]+\d/.test(s)
}

function hrefOf(s) {
    if (/^www\./i.test(s))
        return "https://" + s
    if (/^(?:mailto|tel):|:\/\//i.test(s))
        return s
    if (s.indexOf("@") >= 0)
        return "mailto:" + s
    return "tel:" + (s.charAt(0) === "+" ? "+" : "") + digitsOf(s)
}

// [{start, end, text, url}] in the order they appear.
function find(text) {
    var res = []
    if (!text)
        return res
    PATTERN.lastIndex = 0
    var m
    while ((m = PATTERN.exec(text)) !== null) {
        var s = m[0]
        var phone = /^[+(\d]/.test(s) && !/[@:]/.test(s)
        if (phone) {
            if (!isPhone(s, text.charAt(m.index - 1), text.charAt(m.index + s.length)))
                continue
        } else {
            s = trimEnd(s)
            if (s === "" || /^(?:(?:https?|ftp):\/\/|www\.|mailto:|tel:)$/i.test(s))
                continue
        }
        res.push({ start: m.index, end: m.index + s.length, text: s, url: hrefOf(s) })
    }
    return res
}

// "web", "email" or "phone": what opening the link does.
function kind(url) {
    if (/^mailto:/i.test(url))
        return "email"
    if (/^tel:/i.test(url))
        return "phone"
    return "web"
}

// What "Copy" puts on the clipboard: the URL, the bare e-mail address or the phone number.
function address(url) {
    return url.replace(/^(?:mailto|tel):(?:\/\/)?/i, "")
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
