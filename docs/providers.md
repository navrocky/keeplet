# Providers

Keeplet shows notes from several accounts at once. A *provider* knows one service (today: Google Keep);
everything above it (ViewModels, Views) works with a provider-neutral note shape and a capability list.

## Layout
```
code/core/        provider-neutral: notes.js (note shape), workspace.js (merge/filter/sort),
                  errors.js (ProviderError), util.js, migration.js
code/providers/   contract.js (structural check), registry.js, fake.js (tests/previews)
code/providers/keep/   index.js (the provider), gauth.js, keepapi.js, nodes.js
code/providers/local/  index.js (notes stored only on this machine; no service)
```

## Contract
A provider is a JS module (`.pragma library`) exporting:

| Export | Meaning |
|---|---|
| `id`, `name`, `icon` | stable id (`"keep"`), display name, Breeze icon name |
| `capabilities` | `labels: "multi" \| "single" \| "none"`, `colors`, `checklists`, `nestedItems`, `convertType`, `pinned`, `archive`, `trash`, `images`, `offlineEdit`, `persistent`, `labelEdit` (booleans except `labels` and `colors`; `colors` is the list of supported color names, empty = no colors; the first entry is the "no color" default) |
| `credentialFields` | `[{key, label, secret}]` — the sign-in form is generated from this |
| `signIn(creds)` | `Promise<{accountId, displayName, secret, meta}>`; rejects with `ProviderError` (`network`, `badCredentials`, `failed`) |
| `createSession(account, secret, options)` | returns a session (below); `options` is a test hook |

Optional: `browserSignIn` `{startUrl, doneMarker, cookie, credentialKey}` — sign in through a browser window: the
service opens `startUrl`, waits until the URL ends with `doneMarker`, reads `cookie` and the ViewModel passes it to
`signIn` as `creds[credentialKey]` (`email` may be empty; see [decisions/0003](decisions/0003-browser-signin.md)).
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
| `createLabel(state, name)` | *(if `capabilities.labelEdit`)* creates a label; `{id, name}` or `null` for an empty or taken name (names are unique per account, ignoring case); queued like an edit |
| `renameLabel(state, id, name)` | *(if `capabilities.labelEdit`)* renames a label (notes show the new name); `false` for an empty/taken name or unknown id |
| `deleteLabel(state, id)` | *(if `capabilities.labelEdit`)* deletes a label; its notes stay and just lose it |
| `reorder(state, noteId, order)` | *(if `capabilities.reorder`)* puts a note at `order` in the account's own sequence (descending = top first); returns whether anything changed; queued like an edit |

`persistent`: the session state is the only copy of the data (local provider), not a cache of a service. The
ViewModel then saves it at once after every edit instead of after a quiet period, and an account whose stored
state cannot be read is locked (error `storage`, no edits) so that an empty state never overwrites it.
Signing in to such a provider has no secret, and a name that already exists is rejected (`exists`).

Sessions own their tokens and refresh them internally (Keep: auth token cache, one retry on 401).

Error kinds: `network` (keep showing cached data), `badCredentials` (sign-in), `auth` (stored session no
longer valid → ask to sign in again), `unauthorized`, `failed` (+`detail`).

## Choosing a type and managing accounts
Accounts are added and removed in the settings dialog (page *Accounts*, `ui/configAccounts.qml` →
`views/AccountsSettings.qml`), which has its own `AccountsViewModel` on the same database; it bumps the
hidden `accountsRevision` config key so running widgets reload. The type comes from `registry.list()`; the form
(`SignInView`, `embedded`) is generated from `credentialFields`. The burger menu only opens the settings.

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
