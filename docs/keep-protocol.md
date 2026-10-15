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

_To be refined while porting `node.py` (stage 2–3)._
