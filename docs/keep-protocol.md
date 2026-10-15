# Keep sync protocol

Ported from gkeepapi (`gkeepapi/__init__.py` `KeepAPI`, `gkeepapi/node.py`). Base URL
`https://www.googleapis.com/notes/v1/`. Headers: `Authorization: OAuth <auth token>`,
`Content-Type: application/json`. HTTP 401 → refresh auth token and retry once.

## POST /changes
Request:
```json
{
  "nodes": [ /* locally changed nodes, serialized */ ],
  "clientTimestamp": "2026-10-15T12:00:00.000000Z",
  "requestHeader": {
    "clientSessionId": "s--<ms since epoch>--<random 10 digits>",
    "clientPlatform": "ANDROID",
    "clientVersion": {"major": "9", "minor": "9", "build": "9", "revision": "9"},
    "capabilities": [{"type": "NC"}, {"type": "PI"}, {"type": "LB"}, {"type": "AN"},
                     {"type": "SH"}, {"type": "DR"}, {"type": "TR"}, {"type": "IN"},
                     {"type": "SNB"}, {"type": "MI"}, {"type": "CO"}]
  },
  "targetVersion": "<toVersion from previous response; omitted on first sync>",
  "userInfo": {"labels": [ /* changed labels */ ]}
}
```
Response: `nodes` (changed nodes), `toVersion`, `truncated`, `userInfo.labels`.
Repeat with the new `targetVersion` while `truncated` is true.

## Nodes
Notes are trees of nodes. Top-level notes have `parentId: "root"`.

| type | meaning |
|---|---|
| `NOTE` | text note; its body is a single child `LIST_ITEM` holding `text` |
| `LIST` | checklist; children are `LIST_ITEM`s |
| `LIST_ITEM` | `text`, `checked`, `sortValue`, optional `superListItemId` (indent) |
| `BLOB` | attachment (image, drawing, audio) |

Common fields: `id` (client id), `serverId`, `parentId`, `kind: "notes#node"`, `type`,
`timestamps {created, updated, trashed, deleted, userEdited}`, `baseVersion`.
Top-level extras: `title`, `color` (`DEFAULT`, `RED`, `ORANGE`, `YELLOW`, `GREEN`, `TEAL`,
`BLUE`, `CERULEAN`, `PURPLE`, `PINK`, `BROWN`, `GRAY`), `isArchived`, `isPinned`,
`labelIds [{labelId, deleted}]`, `nodeSettings`, `annotationsGroup`, `collaborators`.

Timestamps are strings `YYYY-MM-DDTHH:MM:SS.ffffffZ`; "not set" is `1970-01-01T00:00:00.000000Z`.
Trashing sets `timestamps.trashed`; deleting sets `timestamps.deleted`.

New ids (gkeepapi `generate_id`): `"%x.%016x" % (ms_since_epoch, random_64bit)`.
`sortValue` for new list items: gkeepapi uses random ints; items sort descending.

## Media
`GET media/<blob serverId>?s=0` (with the same auth) redirects to / returns the image URL.

## Implementation notes
- `code/providers/keep/nodes.js` keeps raw server nodes in the state and derives notes on demand, so nodes sent
  back later carry every field the server gave us.
- Pagination: observed on a real account (276 nodes → `truncated=true`); `code/providers/keep/keepapi.js` follows
  it. Dirty nodes are sent with the first page only (to re-verify at stage 3 when writing).
- `forceFullResync` in a response clears the state and restarts from an empty `targetVersion`.
- Text note body = single child `LIST_ITEM`; checklist items are ordered by descending
  `sortValue`, sub-items follow their parent via `superListItemId`.

## Writing (verified 2026-10-15 on a real account, `spike/run-write.sh`)
Writes use the same `POST /changes`: put changed nodes into `nodes`, keep sending `targetVersion`.
The response is shaped like a pull: `kind, fromVersion, toVersion, nodes, truncated, incremental,
forceFullResync, responseHeader, writeResults`. `nodes` contains the nodes the server accepted (echoed,
with server-added fields); `writeResults` exists but its contents were not inspected.

| Operation | What to send | Observed result |
|---|---|---|
| Create note | top-level `NOTE`/`LIST` node + one child `LIST_ITEM` per body/item; `id` chosen by the client, `parentId: "root"`, `sortValue`, `timestamps` | echoed with `serverId`, `lastModifierEmail`, `moved`, `baseNoteRevision`, `xplatModel`, `representation`; children get `serverId`, `parentServerId`, `nodeSettings`, `annotationsGroup` |
| Edit title / color / pin / archive | the node (copy of the server's version) with the field changed and `timestamps.updated` set | echo matches the sent fields |
| Edit text | the body `LIST_ITEM` with new `text` | echo matches |
| Add checklist item | new `LIST_ITEM`, `parentId` = list id | echoed with `serverId`/`parentServerId` |
| Check item | the item with `checked: true` | accepted; the server then rewrites `sortValue` to a large negative number (checked items sink to the bottom) |
| Indent item | `superListItemId` = id of the item above | server adds `superListItemServerId` |
| Add label | `labelIds: [{labelId, deleted: <never>}]` | echoed as `[{labelId}]` |
| Remove label | the entry with `deleted: <now>` | entry disappears from the echoed `labelIds` |
| Trash | `timestamps.trashed = <now>` | echoed; restore by setting it back to the epoch value |
| Delete for good | `timestamps.deleted = <now>` on the note **and** its items | tombstones come back: `id`, `serverId`, `timestamps.deleted` only |

Facts that shape the implementation:
- **No `baseVersion`** exists on nodes in this API version; edits were accepted using the client `id` and the
  node as returned by the server. Keep the whole raw node (all server-added fields) and change it in place.
- Timestamps may be sent with microseconds (`2026-10-15T22:14:30.559000Z`); the server answers with milliseconds
  and omits `deleted` on live nodes. A text note's body item carries no `sortValue`/`checked` in the echo.
- List items return placeholder timestamps (`1970-01-01T00:00:00.001Z`): do not rely on them.
- Several nodes in one request (parent + children) work; pushes were small, so behavior with a truncated
  reply to a write request was not observed (the client drains further pages with an empty `nodes`).
- Trash then delete both worked in separate requests; deleting a parent requires deleting its items too.
- New list items used random positive `sortValue`s (1e9..1e10); items are displayed by descending `sortValue`.

_Still open:_ the meaning of `writeResults`, reordering existing items (sortValue renumbering), creating and
renaming labels (`userInfo.labels`), images and drawings.
