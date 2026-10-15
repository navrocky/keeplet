# 0002. Accounts are global, display is per widget instance

Status: **accepted** (2026-10-15)

## Context
Until stage 2 the account lived in each widget instance's config (`email`, `androidId`, `secretFallback`),
while the KWallet entry and the notes cache were shared per user. Consequences: every new widget needed a new
sign-in, "Sign Out" in one instance deleted the KWallet entry another instance relied on, the fallback secret
was visible to one instance only, and two instances of one account wrote one cache independently.

## Decision
- **Global (per user), via `AccountsService` + `LocalDb`:** account registry, secrets (KWallet when enabled,
  otherwise the shared local database), per-account notes cache.
- **Per widget instance (`Plasmoid.configuration`):** `accountKeys` (which accounts this widget shows, empty = all),
  `syncInterval`, and later UI state such as the collapsed label rail.
- Several providers/accounts are active at once; the note list is the merge of the accounts in scope.
- "Sign out" in a widget removes the account globally (registry, secret, cache); there is no per-instance sign-out.
- Legacy single-account configuration is migrated on first start (`AccountsService.migrateLegacy`):
  account `keep:<email>`, secret read from the old per-instance fallback or the old KWallet key.

## Consequences / trade-offs
- **Secrets without KWallet are stored in the shared SQLite file** (`~/.local/share/plasmashell/QML/OfflineStorage/`),
  readable by anyone who can read the user's files (file mode is not controllable from QML). Before, the
  per-instance fallback lived in `plasma-org.kde.plasma.desktop-appletsrc` (mode 0600). Enabling KWallet removes this
  trade-off; the README says so.
- The notes cache holds note contents in the same file. An option "don't store notes on disk" is planned.
- Two instances of the same account sync independently. Harmless while the widget only reads; with the
  write path (stage C) a single sync owner per account is required (shared singleton or a lease in the database).
