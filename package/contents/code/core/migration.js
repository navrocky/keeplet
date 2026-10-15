.pragma library

// Upgrade from the single-account, per-instance config layout (stages 1-2):
//   configuration.email / androidId / secretFallback  ->  account "keep:<email>" in the shared registry.
// Pure planning; the service performs the I/O.

// Returns {account, legacySecretKey, inlineSecret} or null when there is nothing to migrate.
function planLegacy(config) {
    var email = config && config.email ? String(config.email).trim() : ""
    if (!email)
        return null
    return {
        account: {
            key: "keep:" + email,
            providerId: "keep",
            accountId: email,
            displayName: email,
            meta: { androidId: config.androidId || "" }
        },
        // KWallet entry written by the old layout is keyed by the bare e-mail.
        legacySecretKey: email,
        inlineSecret: config.secretFallback || ""
    }
}
