package com.ktwallet.core_crypto

/** Retry exactly once through the authentication provider, only for an
 * explicitly recoverable expired-auth error. Never swallow storage failures.
 */
internal fun <T> authenticatedRead(
    action: () -> T,
    requiresAuthentication: (Exception) -> Boolean,
    authenticate: (() -> T) -> Unit,
    complete: (T) -> Unit,
) {
    val value = try {
        action()
    } catch (error: Exception) {
        if (!requiresAuthentication(error)) throw error
        authenticate(action)
        return
    }
    complete(value)
}
