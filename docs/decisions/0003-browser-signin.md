# 0003. Sign-in through an embedded browser window

Status: **accepted** (2026-10-17) — the main way to sign in to Keep; pasting `oauth_token` stays as the alternative.

## Question
Can the widget show Google's sign-in itself and take the one-time `oauth_token` without the user opening DevTools?

## Spikes (`spike/webauth.qml`, `spike/webauth-email.qml`; Qt 6.11, QtWebEngine)
- `WebEngineView` loads `https://accounts.google.com/EmbeddedSetup` (passkey, password, 2-step all work).
- The flow ends when the consent page ("I agree") changes the URL fragment to **`#close`** — the signal Android's
  WebView host uses too. No navigation to another page happens.
- `oauth_token` is **HttpOnly**: `document.cookie` shows only `OTZ`; the QML `WebEngineProfile` has no cookie store.
- **Works:** attach a DevTools view (`view.devToolsView = dev`) and call `InspectorFrontendHost.sendMessageToBackend`
  with `Network.getAllCookies`; the reply lists HttpOnly cookies (`oauth_token`, `user_id`, …). The DevTools view can be
  1x1 and transparent. DevTools logs an unexpected reply, cookie values included, so the hook must swallow it.
- `exchange_token` accepts an **empty `Email`**; the page also shows the address (fallback).

## Decision
- `services/BrowserSignIn.qml` + `BrowserSignInWindow.qml`: a window with an off-the-record profile, destroyed after use.
  Only the window file imports `QtWebEngine`; if the module is missing, `available` is false and only the manual form is shown.
- The provider declares `browserSignIn {startUrl, doneMarker, cookie, credentialKey}`; the ViewModel
  (`signInWithBrowser`) turns the captured token into `provider.signIn({email, <credentialKey>: token})`.
- Account id: a typed e-mail wins, otherwise the `Email` Google returns from `exchange_token`.
- The sign-in form shows "Sign in with Google" first; "Enter token manually" is the alternative.

## Consequences
- Still no native code. `QtWebEngine` is a runtime dependency of the system, optional for the widget.
- Relies on DevTools internals (`DevToolsAPI`, `InspectorFrontendHost`); if a Qt update breaks them the window reports
  `failed` ("cookie not found") and the user falls back to the manual form.
- Nothing from the Google session stays on disk (private profile); the password never reaches the widget.
