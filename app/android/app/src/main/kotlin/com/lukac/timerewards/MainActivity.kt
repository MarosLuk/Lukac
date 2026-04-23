package com.lukac.timerewards

import android.Manifest
import android.app.AppOpsManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ResolveInfo
import android.os.Build
import android.os.Process
import android.provider.CalendarContract
import android.provider.Settings
import android.text.TextUtils
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.lukac.timerewards/enforcement"
    private val calendarPermRequestCode = 2001
    private var pendingCalendarResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "heartbeat" -> {
                    getSharedPreferences("time_rewards_blocker", Context.MODE_PRIVATE)
                        .edit()
                        .putLong("last_heartbeat_ms", System.currentTimeMillis())
                        .apply()
                    result.success(true)
                }
                "hasPermissions" -> result.success(hasPermissions())
                "hasUsageAccess" -> result.success(hasUsageAccess())
                "hasAccessibilityAccess" -> result.success(isAccessibilityEnabled())
                "openUsageAccessSettings" -> {
                    startActivity(
                        Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                    )
                    result.success(true)
                }
                "openAccessibilitySettings" -> {
                    startActivity(
                        Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                    )
                    result.success(true)
                }
                "requestPermissions" -> {
                    requestPermissions()
                    result.success(true)
                }
                "listInstalledApps" -> result.success(listInstalledApps())
                "listEssentialApps" -> result.success(listEssentialApps())
                "pickApps" -> result.notImplemented()
                "pickAllowedApps" -> result.notImplemented()
                "applyShield" -> {
                    val pkgs = call.argument<List<String>>("packages") ?: emptyList()
                    val allowed = call.argument<List<String>>("allowed") ?: emptyList()
                    AppBlockerService.updateBlocklist(
                        this,
                        blocked = pkgs,
                        allowed = allowed,
                        shieldActive = true,
                    )
                    result.success(null)
                }
                "clearShield" -> {
                    // Preserve the current allow-list so it is available the
                    // next time the shield is applied.
                    val currentAllowed = AppBlockerService.readAllowed(this)
                    AppBlockerService.updateBlocklist(
                        this,
                        blocked = emptyList(),
                        allowed = currentAllowed,
                        shieldActive = false,
                    )
                    result.success(null)
                }
                "setAllowList" -> {
                    val allowed = call.argument<List<String>>("packages") ?: emptyList()
                    AppBlockerService.updateAllowList(this, allowed)
                    result.success(null)
                }
                "hasCalendarAccess" -> result.success(hasCalendarPermission())
                "requestCalendarAccess" -> {
                    if (hasCalendarPermission()) {
                        result.success(true)
                    } else if (pendingCalendarResult != null) {
                        // An earlier call is still waiting for the system dialog.
                        result.success(false)
                    } else {
                        pendingCalendarResult = result
                        ActivityCompat.requestPermissions(
                            this,
                            arrayOf(Manifest.permission.READ_CALENDAR),
                            calendarPermRequestCode,
                        )
                    }
                }
                "listCalendarEvents" -> {
                    val from = (call.argument<Number>("fromMs"))?.toLong()
                        ?: System.currentTimeMillis()
                    val to = (call.argument<Number>("toMs"))?.toLong()
                        ?: (from + 14L * 24 * 3600 * 1000)
                    if (!hasCalendarPermission()) {
                        result.error(
                            "PERMISSION_DENIED",
                            "READ_CALENDAR not granted",
                            null,
                        )
                    } else {
                        result.success(listCalendarEvents(from, to))
                    }
                }
                "hasNotificationAccess" -> result.success(hasNotificationAccess())
                "requestNotificationAccess" -> {
                    startActivity(
                        Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                    )
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun hasPermissions(): Boolean = hasUsageAccess() && isAccessibilityEnabled()

    private fun requestPermissions() {
        if (!hasUsageAccess()) {
            startActivity(
                Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
            )
            return
        }
        if (!isAccessibilityEnabled()) {
            startActivity(
                Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
            )
        }
    }

    private fun hasUsageAccess(): Boolean {
        val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                packageName
            )
        } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                packageName
            )
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun isAccessibilityEnabled(): Boolean {
        val expected = "$packageName/${AppBlockerService::class.java.name}"
        val enabled = Settings.Secure.getString(
            contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: return false
        val splitter = TextUtils.SimpleStringSplitter(':')
        splitter.setString(enabled)
        while (splitter.hasNext()) {
            if (splitter.next().equals(expected, ignoreCase = true)) return true
        }
        return false
    }

    private fun hasNotificationAccess(): Boolean {
        val expected = "$packageName/${NotificationMuteService::class.java.name}"
        val enabled = Settings.Secure.getString(
            contentResolver,
            "enabled_notification_listeners"
        ) ?: return false
        val splitter = TextUtils.SimpleStringSplitter(':')
        splitter.setString(enabled)
        while (splitter.hasNext()) {
            if (splitter.next().equals(expected, ignoreCase = true)) return true
        }
        return false
    }

    private fun hasCalendarPermission(): Boolean =
        ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.READ_CALENDAR,
        ) == PackageManager.PERMISSION_GRANTED

    /**
     * Reads the event *instances* in the requested window across ALL
     * calendars the device has synced. Uses `Instances` (not `Events`) so
     * recurring meetings expand correctly. Returns a plain list of maps
     * keyed by eventId/title/beginMs/endMs/calendar for the Flutter side.
     */
    private fun listCalendarEvents(
        fromMs: Long,
        toMs: Long,
    ): List<Map<String, Any?>> {
        val results = mutableListOf<Map<String, Any?>>()
        val uri = CalendarContract.Instances.CONTENT_URI.buildUpon()
            .appendPath(fromMs.toString())
            .appendPath(toMs.toString())
            .build()
        val projection = arrayOf(
            CalendarContract.Instances.EVENT_ID,
            CalendarContract.Instances.TITLE,
            CalendarContract.Instances.BEGIN,
            CalendarContract.Instances.END,
            CalendarContract.Instances.CALENDAR_DISPLAY_NAME,
            CalendarContract.Instances.ALL_DAY,
        )
        try {
            contentResolver.query(
                uri,
                projection,
                null,
                null,
                "${CalendarContract.Instances.BEGIN} ASC",
            )?.use { cursor ->
                while (cursor.moveToNext()) {
                    results.add(
                        mapOf(
                            "eventId" to cursor.getLong(0),
                            "title" to (cursor.getString(1) ?: ""),
                            "beginMs" to cursor.getLong(2),
                            "endMs" to cursor.getLong(3),
                            "calendar" to (cursor.getString(4) ?: ""),
                            "allDay" to (cursor.getInt(5) != 0),
                        )
                    )
                }
            }
        } catch (_: SecurityException) {
            // Permission was revoked between the check and the query.
        }
        return results
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == calendarPermRequestCode) {
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingCalendarResult?.success(granted)
            pendingCalendarResult = null
        }
    }

    /**
     * Resolves a small canonical set of "essential" apps the user typically
     * needs reachable even while the shield is active: the default dialer,
     * the default SMS app, the default maps app, and the default clock.
     *
     * We intentionally only include apps that are actually installed and
     * answer to the canonical intents, so on a device that doesn't have,
     * say, a maps app, it is simply omitted.
     */
    private fun listEssentialApps(): List<Map<String, String>> {
        val pm = packageManager
        val candidates = listOf(
            Intent(Intent.ACTION_DIAL),
            Intent(Intent.ACTION_SENDTO, android.net.Uri.parse("smsto:")),
            Intent(Intent.ACTION_VIEW, android.net.Uri.parse("geo:0,0")),
            Intent(android.provider.AlarmClock.ACTION_SHOW_ALARMS),
        )
        val seen = HashSet<String>()
        val results = mutableListOf<Map<String, String>>()
        for (intent in candidates) {
            val info: ResolveInfo? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                pm.resolveActivity(intent, PackageManager.ResolveInfoFlags.of(0L))
            } else {
                @Suppress("DEPRECATION")
                pm.resolveActivity(intent, 0)
            }
            val pkg = info?.activityInfo?.packageName ?: continue
            if (pkg == packageName) continue
            if (!seen.add(pkg)) continue
            val label = info.loadLabel(pm).toString()
            results.add(mapOf("packageName" to pkg, "label" to label))
        }
        return results.sortedBy { it["label"]!!.lowercase() }
    }

    private fun listInstalledApps(): List<Map<String, String>> {
        val pm = packageManager
        val intent = Intent(Intent.ACTION_MAIN).apply {
            addCategory(Intent.CATEGORY_LAUNCHER)
        }
        val resolved: List<ResolveInfo> = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            pm.queryIntentActivities(
                intent,
                PackageManager.ResolveInfoFlags.of(0L)
            )
        } else {
            @Suppress("DEPRECATION")
            pm.queryIntentActivities(intent, 0)
        }
        val seen = HashSet<String>()
        return resolved
            .mapNotNull { info ->
                val pkg = info.activityInfo?.packageName ?: return@mapNotNull null
                if (pkg == packageName) return@mapNotNull null
                if (!seen.add(pkg)) return@mapNotNull null
                mapOf(
                    "packageName" to pkg,
                    "label" to info.loadLabel(pm).toString()
                )
            }
            .sortedBy { it["label"]!!.lowercase() }
    }
}
