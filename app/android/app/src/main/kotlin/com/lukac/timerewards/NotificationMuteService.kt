package com.lukac.timerewards

import android.content.Context
import android.content.SharedPreferences
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

/**
 * Silently dismisses notifications from blocked apps while the shield is
 * active, so their badges/sounds don't tempt the user.
 *
 * Reads the same SharedPreferences file as [AppBlockerService] so both
 * services share a single source of truth for the blocked/allowed sets.
 *
 * The Android framework binds/unbinds this listener automatically based
 * on the user's choice in Settings → Notifications → Device & app
 * notifications. We must NOT try to bind/unbind it from code.
 */
class NotificationMuteService : NotificationListenerService() {

    private val prefs: SharedPreferences by lazy {
        applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null) return
        if (!prefs.getBoolean(KEY_SHIELD_ACTIVE, false)) return

        val pkg = sbn.packageName ?: return
        if (pkg == applicationContext.packageName) return

        val allowed = prefs.getStringSet(KEY_ALLOWED, emptySet()) ?: emptySet()
        if (pkg in allowed) return

        val blocked = prefs.getStringSet(KEY_BLOCKED, emptySet()) ?: emptySet()
        if (pkg in blocked) {
            cancelNotification(sbn.key)
        }
    }

    companion object {
        private const val PREFS = "time_rewards_blocker"
        private const val KEY_BLOCKED = "blocked_packages"
        private const val KEY_ALLOWED = "allowed_packages"
        private const val KEY_SHIELD_ACTIVE = "shield_active"
    }
}
