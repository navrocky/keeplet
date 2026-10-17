import QtQuick
import QtTest
import "../package/contents/code/core/workspace.js" as WS
import "../package/contents/code/core/notes.js" as Notes

TestCase {
    name: "Workspace"

    readonly property var keep: ({ key: "keep:a@x", providerId: "keep" })
    readonly property var other: ({ key: "fake:b", providerId: "fake" })

    function n(props) { return Notes.makeNote(props) }

    function parts() {
        return [
            WS.annotate(keep, [
                n({ id: "k1", title: "Alpha", order: 30, updated: "2026-01-01T00:00:00Z", labels: [{ id: "L1", name: "Work" }] }),
                n({ id: "k2", title: "Beta", order: 20, pinned: true, updated: "2026-01-02T00:00:00Z" }),
                n({ id: "k3", title: "Gamma", order: 10, archived: true }),
                n({ id: "k4", title: "Delta", order: 5, trashed: true })
            ], [{ id: "L1", name: "Work" }]),
            WS.annotate(other, [
                n({ id: "o1", title: "Omega", order: 1, updated: "2026-03-01T00:00:00Z", labels: [{ id: "L1", name: "Work" }] }),
                n({ id: "o2", title: "Sigma", order: 99, updated: "2026-02-01T00:00:00Z" })
            ], [{ id: "L1", name: "Work" }])
        ]
    }

    function ids(list) { return list.map(function (x) { return x.id }).join() }

    function test_annotateTagsNotesAndLabels() {
        var m = WS.merge(parts())
        compare(m.notes.length, 6)
        compare(m.notes[0].accountKey, "keep:a@x")
        compare(m.notes[0].key, "keep:a@x/k1")
        compare(m.notes[0].labels[0].key, "keep:a@x|L1")
        compare(m.labels.length, 2)
    }

    function test_sameLabelIdInTwoAccountsStaysDistinct() {
        var m = WS.merge(parts())
        var keys = m.labels.map(function (l) { return l.key })
        compare(keys.join(), "keep:a@x|L1,fake:b|L1")
    }

    function test_singleAccountUsesProviderOrderPinnedFirst() {
        var all = WS.merge(parts()).notes
        var out = WS.visibleNotes(all, { accountFilter: "keep:a@x", accountCount: 2 })
        compare(ids(out), "k2,k1")   // pinned first; archived and trashed hidden
    }

    function test_multipleAccountsSortByUpdated() {
        var all = WS.merge(parts()).notes
        var out = WS.visibleNotes(all, { accountFilter: "", accountCount: 2 })
        compare(ids(out), "k2,o1,o2,k1")   // pinned k2; then updated desc
    }

    function test_oneAccountInScopeUsesOrderEvenWithoutFilter() {
        var all = WS.merge(parts().slice(0, 1)).notes
        compare(ids(WS.visibleNotes(all, { accountFilter: "", accountCount: 1 })), "k2,k1")
    }

    function test_viewsArchiveAndTrash() {
        var all = WS.merge(parts()).notes
        compare(ids(WS.visibleNotes(all, { view: "archive", accountCount: 2 })), "k3")
        compare(ids(WS.visibleNotes(all, { view: "trash", accountCount: 2 })), "k4")
    }

    function test_labelFilterIsPerAccount() {
        var all = WS.merge(parts()).notes
        compare(ids(WS.visibleNotes(all, { labelKey: "keep:a@x|L1", accountCount: 2 })), "k1")
        compare(ids(WS.visibleNotes(all, { labelKey: "fake:b|L1", accountCount: 2 })), "o1")
    }

    function test_singleAccountOptionSortsByOrder() {
        var a = [{ key: "x/1", accountKey: "x", labels: [], items: [], title: "", text: "", updated: "9", order: 1, pinned: false, archived: false, trashed: false },
                 { key: "x/2", accountKey: "x", labels: [], items: [], title: "", text: "", updated: "1", order: 2, pinned: false, archived: false, trashed: false }]
        compare(WS.visibleNotes(a, { accountCount: 2 }).map(function (n) { return n.key }).join(), "x/1,x/2")
        compare(WS.visibleNotes(a, { accountCount: 2, singleAccount: true }).map(function (n) { return n.key }).join(), "x/2,x/1")
    }

    function test_unlabeledAccountFiltersByAccount() {
        var a = [{ key: "x/1", accountKey: "x", labels: [], items: [], title: "", text: "", updated: "1", order: 1, pinned: false, archived: false, trashed: false },
                 { key: "y/1", accountKey: "y", labels: [], items: [], title: "", text: "", updated: "2", order: 1, pinned: false, archived: false, trashed: false },
                 { key: "x/2", accountKey: "x", labels: [{ key: "x|L" }], items: [], title: "", text: "", updated: "3", order: 2, pinned: false, archived: false, trashed: false }]
        compare(WS.visibleNotes(a, { unlabeledAccount: "x", accountCount: 2 }).map(function (n) { return n.key }).join(), "x/1")
    }

    function test_unlabeledOnlyActiveNotesWithoutLabels() {
        var all = WS.merge(parts()).notes
        // k1 and o1 have labels; k3 is archived, k4 trashed.
        compare(ids(WS.visibleNotes(all, { unlabeled: true, accountCount: 2 })).split(",").sort().join(), "k2,o2")
    }

    function test_searchMatchesTitleBodyItemsAndLabelName() {
        var all = WS.merge(parts()).notes
        compare(ids(WS.visibleNotes(all, { query: "OMEGA", accountCount: 2 })), "o1")
        compare(ids(WS.visibleNotes(all, { query: "work", accountCount: 2 })).split(",").sort().join(), "k1,o1")
        compare(ids(WS.visibleNotes(all, { query: "  ", accountCount: 2 })).split(",").length, 4)
    }
}
