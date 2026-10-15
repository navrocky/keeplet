# 0001. Native auth helper: needed or not?

Status: **open** — waiting for spike A on a real account.

## Question
Can the widget stay pure QML/JS, or does it need a bundled static helper (`keeplet-auth`, Rust)
for authentication and/or secret storage?

## Spikes (`spike/`)
**A. Auth chain from QML XHR** (`spike/run-auth.sh`): exchange_token → perform_oauth → `/changes`.
- Plumbing verified: requests are sent, responses parsed, state file handling works.
- QML XHR sends custom `User-Agent` and `Authorization` unchanged; Qt appends `;charset=UTF-8`
  to `Content-Type`.
- With a fake token both Qt and curl get `403 Error=BadAuthentication` — inconclusive for the
  TLS-fingerprint question.
- Real account: _pending._

**B. Secret storage from QML** (`spike/wallet.qml`): **passed.**
- `org.kde.plasma.workspace.dbus` (part of plasma-workspace 6) can call `org.kde.kwalletd6`:
  isEnabled → networkWallet → open → writePassword → readPassword → removeEntry all work.
- No subprocess, so secrets never show up in `ps`.
- KWallet can be disabled by the user (it is on the dev machine: `Enabled=false`), in which case
  kwalletd6 refuses to start → a fallback store is required.
- Secret Service (`org.freedesktop.secrets`) can't be used: needs struct args the module can't build.

**C. Rust helper prototype** — only if A fails.

## Decision
- Storage: KWallet via D-Bus when enabled, widget config (0600) otherwise. No helper needed for storage.
- Auth helper: _decided after A._
  - A passes → **Q**: pure QML, gpsoauth ported to `contents/code/gauth.js`. No Rust.
  - A fails with `BadAuthentication` for Qt but works with a different TLS client → **R**:
    `keeplet-auth` static binary for `/auth` only; `/changes` stays in QML if it works.
