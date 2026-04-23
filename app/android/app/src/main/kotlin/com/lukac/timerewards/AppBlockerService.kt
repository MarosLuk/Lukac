package com.lukac.timerewards

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.provider.Settings
import android.view.accessibility.AccessibilityEvent

/**
 * Watches foreground-app transitions and, when the shield is active, sends
 * the user back HOME for any package that is NOT on the user's allow-list.
 *
 * Semantics: deny-by-default. While the shield is active, only packages on
 * the allow-list (plus the active launcher, active IME, SystemUI, and this
 * app itself) are permitted to run in the foreground. The old "blocked"
 * list is retained in prefs for backward compatibility but no longer drives
 * the enforcement decision.
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

        // Only enforce while the Flutter side is alive. The main isolate
        // writes a heartbeat every ~2s; if we haven't seen one recently we
        // assume the user force-closed the app and disable enforcement so
        // the device isn't stuck behind the shield.
        val lastHeartbeat = prefs.getLong(KEY_LAST_HEARTBEAT, 0L)
        if (System.currentTimeMillis() - lastHeartbeat > HEARTBEAT_STALE_MS) return

        // Never touch our own app — the user must be able to reach the UI
        // to disable the shield or edit the allow-list.
        if (pkg == applicationContext.packageName) return
        // Never touch core system surfaces.
        if (pkg in SYSTEM_PACKAGES) return
        // Never touch the active home launcher: if we sent it HOME we'd
        // immediately re-trigger ourselves and lock the device in a loop.
        if (pkg == resolveHomeLauncher()) return
        // Never touch the active IME — keyboards present themselves as
        // foreground windows on some OEM skins.
        if (pkg == resolveCurrentIme()) return

        val allowed = prefs.getStringSet(KEY_ALLOWED, emptySet()) ?: emptySet()
        if (pkg in allowed) return

        // Deny-by-default.
        performGlobalAction(GLOBAL_ACTION_HOME)
    }

    override fun onInterrupt() = Unit

    private fun resolveHomeLauncher(): String? {
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
        return packageManager
            .resolveActivity(intent, 0)
            ?.activityInfo
            ?.packageName
    }

    private fun resolveCurrentIme(): String? {
        val component = Settings.Secure.getString(
            contentResolver,
            Settings.Secure.DEFAULT_INPUT_METHOD,
        ) ?: return null
        // Format is "com.example/.SomeImeService" — take the package prefix.
        return component.substringBefore('/').takeIf { it.isNotEmpty() }
    }

    companion object {
        private const val PREFS = "time_rewards_blocker"
        private const val KEY_BLOCKED = "blocked_packages"
        private const val KEY_ALLOWED = "allowed_packages"
        private const val KEY_SHIELD_ACTIVE = "shield_active"
        private const val KEY_LAST_HEARTBEAT = "last_heartbeat_ms"
        private const val HEARTBEAT_STALE_MS = 2_500L

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
