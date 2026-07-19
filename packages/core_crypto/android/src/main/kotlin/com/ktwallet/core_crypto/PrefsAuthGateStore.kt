package com.ktwallet.core_crypto

import android.content.Context

/**
 * SharedPreferences-backed [AuthGateStore] so the lockout ladder survives
 * process death (detailed-design.md §2.4). Counters are non-sensitive.
 * Uninstall clears them (product decision).
 */
class PrefsAuthGateStore(context: Context) : AuthGateStore {
    private val prefs =
        context.getSharedPreferences("kt_core_crypto_auth", Context.MODE_PRIVATE)

    override var failCount: Int
        get() = prefs.getInt(KEY_FAIL, 0)
        set(value) = prefs.edit().putInt(KEY_FAIL, value).apply()

    override var lockedUntilMillis: Long
        get() = prefs.getLong(KEY_UNTIL, 0)
        set(value) = prefs.edit().putLong(KEY_UNTIL, value).apply()

    private companion object {
        const val KEY_FAIL = "fail_count"
        const val KEY_UNTIL = "locked_until"
    }
}
