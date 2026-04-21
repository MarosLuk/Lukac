package com.lukac.timerewards

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.content.SharedPreferences
import android.view.accessibility.AccessibilityEvent

/**
 * Watches foreground-app transitions and, when the shield is active, sends
 * the user back HOME if they open a blocked package.
 *
 * Configuration is stored in SharedPreferences so it survives process death
 * and can be updated from MainActivity without rebinding the service.
 */
class AppBlockerService : AccessibilityService() {

    private val prefs: SharedPreferences by lazy {
        applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return
        if (event.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
        val pkg = event.packageName?.toString() ?: return

        val shieldActive = prefs.getBoolean(KEY_SHIELD_ACTIVE, false)
        if (!shieldActive) return

        // Allow-list takes precedence over the blocked set. An always-allowed
        // package is never sent home, even if it somehow ended up in both
        // sets (the UI enforces mutual exclusion, but be defensive here).
        val allowed = prefs.getStringSet(KEY_ALLOWED, emptySet()) ?: emptySet()
        if (pkg in allowed) return

        val blocked = prefs.getStringSet(KEY_BLOCKED, emptySet()) ?: emptySet()
        if (blocked.isEmpty()) return
        if (pkg == applicationContext.packageName) return
        if (pkg in SYSTEM_PACKAGES) return

        if (pkg in blocked) {
            performGlobalAction(GLOBAL_ACTION_HOME)
        }
    }

    override fun onInterrupt() = Unit

    companion object {
        private const val PREFS = "time_rewards_blocker"
        private const val KEY_BLOCKED = "blocked_packages"
        private const val KEY_ALLOWED = "allowed_packages"
        private const val KEY_SHIELD_ACTIVE = "shield_active"

        private val SYSTEM_PACKAGES = setOf(
            "com.android.systemui",
            "android",
        )

        fun updateBlocklist(
            context: Context,
            blocked: List<String>,
            allowed: List<String>,
            shieldActive: Boolean,
        ) {
            context.applicationContext
                .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit()
                .putStringSet(KEY_BLOCKED, blocked.toSet())
                .putStringSet(KEY_ALLOWED, allowed.toSet())
                .putBoolean(KEY_SHIELD_ACTIVE, shieldActive)
                .apply()
        }

        /** Updates just the allow-list without touching the shield state. */
        fun updateAllowList(context: Context, allowed: List<String>) {
            context.applicationContext
                .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit()
                .putStringSet(KEY_ALLOWED, allowed.toSet())
                .apply()
        }

        fun readAllowed(context: Context): List<String> {
            val set = context.applicationContext
                .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getStringSet(KEY_ALLOWED, emptySet()) ?: emptySet()
            return set.toList()
        }
    }
}
