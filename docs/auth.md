# Authentication

Port of [gpsoauth](https://github.com/simon-weber/gpsoauth) as used by gkeepapi.
Password login is not supported (Google blocks it); the widget needs the one-time `oauth_token` cookie.

## Chain
1. **oauth_token** — single use. Main way: the widget opens <https://accounts.google.com/EmbeddedSetup> in its own
   window (`ui/services/BrowserSignIn*.qml`, QtWebEngine), waits for the `#close` URL fragment and reads the HttpOnly
   cookie through the DevTools protocol ([decisions/0003-browser-signin.md](decisions/0003-browser-signin.md)).
   Alternative: the user signs in in any browser and pastes the cookie (DevTools → Application/Storage → Cookies).
   The browser flow does not know the e-mail: `exchange_token` is sent with an empty `Email` and the answer's
   `Email` becomes the account id (a typed address wins).
2. **exchange_token** → master token (`aas_et/…`, long-lived, full account access).
3. **perform_oauth** → auth token for Keep (`Auth`, `Expiry` ≈ 1 h).
4. Keep requests send `Authorization: OAuth <auth token>`.

All `/auth` calls: `POST https://android.clients.google.com/auth`,
`Content-Type: application/x-www-form-urlencoded`, `User-Agent: GoogleAuth/1.4`.
Response is `key=value` lines; on failure `Error=<code>` (e.g. `BadAuthentication`) with HTTP 403.

`androidId` is a random 16-hex-digit id generated once per login and stored next to the master token.

### exchange_token form
```
accountType=HOSTED_OR_GOOGLE  Email=<email>  has_permission=1  add_account=1  ACCESS_TOKEN=1
Token=<oauth_token>  service=ac2dm  source=android  androidId=<id>
device_country=us  operatorCountry=us  lang=en  sdk_version=17
client_sig=38918a453d07199354f8b19af05ec6562ced5788  callerSig=<same>  droidguard_results=dummy123
```
Result: `Token=<master token>`.

### perform_oauth form
```
accountType=HOSTED_OR_GOOGLE  Email=<email>  has_permission=1  EncryptedPasswd=<master token>
service=oauth2:https://www.googleapis.com/auth/memento https://www.googleapis.com/auth/reminders
source=android  androidId=<id>  app=com.google.android.keep
client_sig=38918a453d07199354f8b19af05ec6562ced5788
device_country=us  operatorCountry=us  lang=en  sdk_version=17
```
Result: `Auth=<token>`, `Expiry=<unix seconds>`.

## TLS fingerprint caveat
gpsoauth forces an Android-like cipher list because `/auth` has rejected some TLS clients.
Qt's TLS stack cannot be tuned from QML, but as of 2026-10 `/auth` accepts it
([decisions/0001-auth-helper.md](decisions/0001-auth-helper.md)). If logins start failing with
`BadAuthentication` for valid tokens, suspect this first.

## Storing the master token
Preferred: KWallet over D-Bus from QML (`org.kde.plasma.workspace.dbus`, ships with Plasma 6),
service `org.kde.kwalletd6`, path `/modules/kwalletd6`, interface `org.kde.KWallet`:
`isEnabled()`, `networkWallet()`, `open(wallet, int64 wId=0, appId)`,
`writePassword/readPassword/removeEntry(handle, "Keeplet", <email>, …, appId)`.

Fallback when KWallet is disabled (`isEnabled() == false`, e.g. `Enabled=false` in `kwalletrc`):
the shared `LocalDb` (namespace `secrets`). It is a plain SQLite file with the user's default file mode,
so it is weaker than the old per-instance config key — see
[decisions/0002-accounts-and-storage.md](decisions/0002-accounts-and-storage.md). A secret saved in the
fallback is still read after KWallet gets enabled, and moves to KWallet on the next sign-in.
Secrets are keyed `<providerId>:<accountId>`; the pre-0.1 key (bare e-mail) is migrated on first start.

Implementation: `ui/services/SecretStore.qml` (storage), `code/providers/keep/index.js` (sign-in and
session with auth-token cache and refresh), `code/providers/keep/gauth.js` (HTTP). `kwalletd6` reads `Enabled`
only at startup; after toggling it run `qdbus6 org.kde.kwalletd6 /modules/kwalletd6 reconfigure`.

## Errors
- `BadAuthentication` on exchange → `badCredentials`: token wrong/expired/used; user gets a fresh `oauth_token`.
- `BadAuthentication` on perform_oauth → `auth`: master token revoked; the account is flagged and the user is asked to sign in again.
- Network errors (`network`) never affect the stored session; cached notes stay visible.

D-Bus module gotchas (verified in `spike/wallet.qml`):
- `SessionBus.asyncCall(msg, resolve, reject)` — both callbacks get the `DBusPendingReply`; use `reply.value` / `reply.error`.
- Don't set `msg.signature` — explicit signatures are rejected ("Invalid signature for method").
- Pass `int64`/`int32` via `new DBus.int64(x)` / `new DBus.int32(x)`; strings as plain JS.
- Some replies come wrapped as `{value: …}` — unwrap.
- Secret Service (`org.freedesktop.secrets`) needs struct arguments, which the module can't build, so it's not used.
