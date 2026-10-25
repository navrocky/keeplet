# Usage statistics

Keeplet can send anonymous usage statistics to Google Analytics 4 (GA4) through the
[Measurement Protocol](https://developers.google.com/analytics/devguides/collection/protocol/ga4)
— a plain HTTPS `POST` from QML, no native code. It is **opt-in**: nothing is sent until the user agrees.

## For users
- The widget asks once (a notice above the notes list): *Allow* / *No, thanks*.
- The choice can be changed at any time: widget settings → General → *Statistics*.
- The choice is shared by all Keeplet widgets of the user. Turning statistics off deletes the random id.
- Builds without the keys compiled in (local builds, forks, `scripts/dev.sh`) never ask and never send.

### What is sent
Each event carries a random id (a UUID generated on opt-in, not tied to any account), a session id
(start time of the widget) and the event time.

| Event | Parameters | When |
|---|---|---|
| `app_start` | `widget_version`, `locale`, `providers` (e.g. `keep,local`), `accounts` (count) | at most once a day |
| `analytics_opt_in` | — | statistics turned on |
| `sign_in` | `provider`, `method` (`password`/`browser`) | an account was added |
| `sign_in_error` | `provider`, `kind` (error code) | sign-in failed |
| `account_remove` | `provider` | an account was removed |
| `sync_error` | `provider`, `kind` (error code) | sync failed (once per new error, not on every retry) |
| `note_create` | `type` (`NOTE`/`LIST`) | new note |
| `note_trash`, `note_restore`, `note_delete`, `trash_empty` | — | |
| `note_archive` | `archived` | |
| `note_pin` | `pinned` | |
| `note_color` | `color` (Keep color name) | |
| `note_move`, `note_drop_label` | — | manual order, drag onto a label |
| `note_convert` | `to` (`NOTE`/`LIST`) | |
| `checklist_clear_done`, `editor_undo`, `editor_redo` | — | |
| `label_create`, `label_rename`, `label_delete` | `provider` | |
| `group_open` | `kind` (`all`/`unlabeled`/`label`/`archive`/`trash`) | |
| `search` | — | once per search, not per keystroke |
| `link_preview` | — | a web link preview was shown |

### What is never sent
Note titles, text and checklist items, label names, e-mail addresses, account ids/keys, tokens,
links, error details (only the error code). The list above is enforced in code:
`package/contents/code/core/analytics.js` (`EVENTS`) drops every event and parameter it does not list.
Google sees the request's IP address, as with any web request.

## How it works
- Model: `code/core/analytics.js` — whitelist (`EVENTS`), `sanitize`, request `payload`, `post`.
- Service: `ui/services/Analytics.qml` — consent, client id and the day of the last heartbeat in `LocalDb`
  (namespace `analytics`, global); a queue sent in batches of up to 25 events after 10 s. Consent is read again
  before each batch and every minute, so a change from another widget or the settings is honored.
- ViewModels take an optional `analytics` ({`track(name, params)`}) and report their commands;
  `AnalyticsViewModel` drives the consent notice and the settings checkbox.
- New event: add it to `EVENTS` (with its parameters), call `_track` in the ViewModel command,
  add a row to the table above.

## Keys
The measurement id and the API secret are substituted into `analytics.js` by `scripts/package.sh` from the
environment variables `GA_MEASUREMENT_ID` and `GA_API_SECRET` (`@GA_…@` placeholders stay otherwise).
Like any key shipped in a client app, the secret is not really secret: it only allows sending events.

### Creating the GA4 property (once)
1. <https://analytics.google.com> → *Admin* → *Create* → *Property*: name `Keeplet`, time zone, currency →
   business details → *Create*.
2. *Choose a platform*: **Web** (the Measurement Protocol works with a web stream);
   URL `https://github.com/navrocky/keeplet`, name `Keeplet widget`. Turn *Enhanced measurement* off.
3. Open the stream: copy the **Measurement ID** (`G-XXXXXXXXXX`).
4. In the same stream: *Measurement Protocol API secrets* → accept the terms → *Create* → nickname
   `keeplet` → copy the **secret value**.
5. *Admin* → *Data display* → *Custom definitions* → *Create custom dimension* (scope *Event*) for each
   parameter you want in reports: `provider`, `kind`, `type`, `method`, `widget_version`, `locale`,
   `providers`, `to`, `color`; *custom metric* `accounts`.
6. *Admin* → *Data collection and modification* → *Data retention*: as short as you need (2 months is the minimum).
7. GitHub repo → *Settings* → *Secrets and variables* → *Actions* → *New repository secret*:
   `GA_MEASUREMENT_ID` and `GA_API_SECRET`. Release builds (`release.yml`) then have statistics on; CI test builds, forks and local builds
   have them off.

### Checking
- Local build with keys: `GA_MEASUREMENT_ID=G-… GA_API_SECRET=… scripts/build.sh`, then `scripts/install.sh`;
  the build log says `== usage statistics: on`.
- Allow statistics in the widget; events appear in GA4 *Reports → Realtime* within a minute
  (*Admin → DebugView* shows single events).
- A request can be validated without recording it: send the same body to
  `https://www.google-analytics.com/debug/mp/collect?measurement_id=…&api_secret=…` — the response lists problems.
