.pragma library

// Checklist <-> text. Items are written the way Markdown task lists are: "- [ ] text", "- [x] text", sub-items
// indented by two spaces. Pure functions; used by the note editor to convert and copy notes.

var LINE = /^(\s*)(?:[-*+]\s+)?\[([ xX]?)\]\s?(.*)$/

// One line per item. Without any checked item the markers are left out: the result is plain text.
// `markers` forces them on (copying to the clipboard).
function toText(items, markers) {
    var any = !!markers || items.some(function (it) { return it.checked })
    return items.map(function (it) {
        var pad = it.indent > 0 ? "  " : ""
        return any ? pad + "- [" + (it.checked ? "x" : " ") + "] " + it.text : it.text
    }).join("\n")
}

// Lines to items: "[x] a", "- [ ] b" give checked / unchecked items, any other non-empty line an unchecked item.
// A line indented by at least one space becomes a sub-item when `nested` is true.
function fromText(text, nested) {
    var items = []
    text.split("\n").forEach(function (line) {
        if (line.trim() === "")
            return
        var m = LINE.exec(line)
        var lead = m ? m[1] : /^\s*/.exec(line)[0]
        items.push({
            id: "",
            text: m ? m[3] : line.trim(),
            checked: !!m && m[2].toLowerCase() === "x",
            indent: nested && lead.length > 0 && items.length > 0 ? 1 : 0
        })
    })
    return items
}
