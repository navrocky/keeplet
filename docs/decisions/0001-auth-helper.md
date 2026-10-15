# 0001. Native auth helper: needed or not?

Status: **accepted** (2026-10-15) — **no helper; the widget is pure QML/JS.**

## Question
Can the widget stay pure QML/JS, or does it need a bundled static helper (`keeplet-auth`, Rust)
for authentication and/or secret storage?

## Spikes (`spike/`)
**A. Auth chain from QML XHR** (`spike/run-auth.sh`): **passed** on a real account (Qt 6.11, Plasma 6.7).
- `exchange_token` → HTTP 200, `Token` = master token (`aas_et/…`). Response also carries
  `Auth`, `SID`, `LSID`, `Email`, `services`, … — only `Token` is used.
- `perform_oauth` → HTTP 200, `Auth` (`ya29.…`) and `Expiry` (~1 h).
- `POST /changes` → HTTP 200: 276 nodes, 40 top-level notes, 3 labels, `truncated=true`
  (pagination is real and must be handled).
- So `/auth` accepts Qt's TLS client (QtNetwork/OpenSSL); no Android cipher list needed.
- QML XHR sends custom `User-Agent` and `Authorization` unchanged; Qt appends `;charset=UTF-8`
  to `Content-Type` — harmless for both endpoints.

**B. Secret storage from QML** (`spike/wallet.qml`): **passed.**
- `org.kde.plasma.workspace.dbus` (part of plasma-workspace 6) can call `org.kde.kwalletd6`:
  isEnabled → networkWallet → open → writePassword → readPassword → removeEntry all work.
- No subprocess, so secrets never show up in `ps`.
- KWallet can be disabled by the user (it is on the dev machine: `Enabled=false`), in which case
  kwalletd6 refuses to start → a fallback store is required.
- Secret Service (`org.freedesktop.secrets`) can't be used: needs struct args the module can't build.

**C. Rust helper prototype** — not needed.

## Decision
- Auth: gpsoauth ported to JS (`contents/code/providers/keep/gauth.js`), requests via `XMLHttpRequest`.
- Storage: KWallet via D-Bus when enabled, widget config (0600) otherwise.
- No native code, no `contents/bin/`, no Rust toolchain in the build image.

## Consequences
- The `.plasmoid` stays architecture-independent and KDE Store–friendly.
- If Google starts rejecting Qt's TLS client, revisit: a helper limited to `/auth`
  (option R from the stage 0 plan) is the fallback.
