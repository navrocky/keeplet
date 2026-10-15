.pragma library

// Provider-neutral error. The View maps `kind` to a user-facing message.
//   "network"        server unreachable; keep showing cached data
//   "badCredentials" sign-in rejected (wrong or used-up token/password)
//   "auth"           stored session is no longer valid: the user must sign in again
//   "unauthorized"   server refused a freshly authorized request
//   "failed"         anything else; `detail` carries the reason
function ProviderError(kind, detail) {
    this.kind = kind
    this.detail = detail || ""
    this.message = kind + (detail ? ": " + detail : "")
}
ProviderError.prototype.toString = function () { return "ProviderError: " + this.message }

function isProviderError(e) {
    return e instanceof ProviderError
}
