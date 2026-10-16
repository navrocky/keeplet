# 0003. Local provider and account management in settings

Status: **accepted** (2026-10-17)

## Context
Keeplet had one provider (Google Keep), accounts were added from the widget and signed out from the burger menu.
Users need a choice of backend type when adding an account, an overview of their accounts, and a backend that
works without any service.

## Decision
- A `local` provider (`code/providers/local`): the session state is the notes themselves. Capability
  `persistent: true` makes the NotesViewModel save the state at once and lock the account if the stored state is
  unreadable. The state lives in the per-account snapshot in the shared database (namespace `cache`).
- Accounts are managed in the settings dialog (page *Accounts*), which runs its own AccountsViewModel on the shared
  database and notifies widgets with the `accountsRevision` config counter. The burger menu offers *Settings…*
  instead of *Sign out*.
- Several accounts of one provider are supported (account key is `<providerId>:<accountId>`).

## Consequences / trade-offs
- Local notes are unencrypted and only as safe as the database file; no export/backup yet.
- The snapshot namespace is named `cache` although it is the primary store for `local`; a separate namespace
  would protect it from a future "clear cache" feature (migration needed), so such a feature must skip persistent accounts.
- Every reload creates new sessions, so widgets rebuild account state from the snapshot after an account change.
