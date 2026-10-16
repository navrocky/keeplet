# Providers

Keeplet shows notes from several accounts at once. A *provider* knows one service (today: Google Keep);
everything above it (ViewModels, Views) works with a provider-neutral note shape and a capability list.

## Layout
```
code/core/        provider-neutral: notes.js (note shape), workspace.js (merge/filter/sort),
                  errors.js (ProviderError), util.js, migration.js
code/providers/   contract.js (structural check), registry.js, fake.js (tests/previews)
code/providers/keep/   index.js (the provider), gauth.js, keepapi.js, nodes.js
```

## Contract
A provider is a JS module (`.pragma library`) exporting:

| Export | Meaning |
|---|---|
| `id`, `name`, `icon` | stable id (`"keep"`), display name, Breeze icon name |
| `capabilities` | `labels: "multi" \| "single" \| "none"`, `colors`, `checklists`, `nestedItems`, `convertType`, `pinned`, `archive`, `trash`, `images`, `offlineEdit` (booleans except `labels` and `colors`; `colors` is the list of supported color names, empty = no colors; the first entry is the "no color" default) |
| `credentialFields` | `[{key, label, secret}]` — the sign-in form is generated from this |
| `signIn(creds)` | `Promise<{accountId, displayName, secret, meta}>`; rejects with `ProviderError` (`network`, `badCredentials`, `failed`) |
| `createSession(account, secret, options)` | returns a session (below); `options` is a test hook |

Optional: `signInHelpUrl` (the View shows provider-specific instructions; user-facing text lives in Views).

Session:

| Method | Meaning |
|---|---|
| `createState()` | empty opaque state (JSON-serializable; cached by the app) |
| `restoreState(obj)` | validated state from cached JSON, or `null` |
| `sync(state)` | `Promise<state>`: pushes the queue of local edits (if the provider supports writing), then pulls; may mutate `state`; rejects with `ProviderError` and keeps the queue |
| `notes(state)` | array of normalized notes (shape in `core/notes.js`) |
| `labels(state)` | `[{id, name}]` |
| `commit(state, snapshot)` | *(if `capabilities.write`)* applies an edited note (new one: empty `id`) to `state` at once and queues it; returns the note as stored, with generated ids |
| `remove(state, noteId)` | *(if `capabilities.write`)* deletes a note for good, queued like an edit |
| `pending(state)` | *(if `capabilities.write`)* number of queued edits |
| `reorder(state, noteId, order)` | *(if `capabilities.reorder`)* puts a note at `order` in the account's own sequence (descending = top first); returns whether anything changed; queued like an edit |

Sessions own their tokens and refresh them internally (Keep: auth token cache, one retry on 401).

Error kinds: `network` (keep showing cached data), `badCredentials` (sign-in), `auth` (stored session no
longer valid → ask to sign in again), `unauthorized`, `failed` (+`detail`).

## Adding a provider
1. Create `code/providers/<id>/index.js` implementing the contract; keep protocol code next to it.
2. Register it in `code/providers/registry.js`.
3. Add provider-specific sign-in instructions to `SignInView.helpText()`.
4. Tests: `Contract.validate(provider)` and `validateSession(session)` must return no problems
   (see `tests/tst_providers.qml`); test the session against a fake transport.
5. Differences to decide: labels vs single category (`capabilities.labels`), colors, nested items.

## Multi-account behavior
- Account key: `"<providerId>:<accountId>"`; note key `"<accountKey>/<noteId>"`; label key `"<accountKey>|<labelId>"`.
  Labels belong to an account, so equal names in different accounts stay separate groups.
- One account in scope → provider's own order (`order`, descending); several → most recently updated first.
  Pinned notes are always first.
- A failure of one account never hides the others (`NotesViewModel.errors` is per account).
