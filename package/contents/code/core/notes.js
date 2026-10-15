.pragma library

// Provider-neutral note shape. Providers return objects of this shape from session.notes().
// See docs/providers.md.
//
//   id        string, unique within the account
//   type      "NOTE" | "LIST"
//   title, text
//   items     [{id, text, checked, indent}]   (LIST only)
//   images    [{id, serverId, mimeType}]
//   color     provider color name; "DEFAULT" when none
//   pinned, archived, trashed
//   labels    [{id, name}]
//   order     number; display order within the account, descending
//   created, updated   ISO-8601 strings ("" if unknown)
//
// The workspace adds accountKey, providerId, key and label.key when merging accounts.

function makeNote(props) {
    var note = {
        id: "", type: "NOTE", title: "", text: "", items: [], images: [],
        color: "DEFAULT", pinned: false, archived: false, trashed: false,
        labels: [], order: 0, created: "", updated: ""
    }
    for (var k in props)
        note[k] = props[k]
    return note
}
