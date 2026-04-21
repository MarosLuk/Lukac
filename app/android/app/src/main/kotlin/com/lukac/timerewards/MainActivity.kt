package com.lukac.timerewards

import android.app.AppOpsManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ResolveInfo
import android.os.Build
import android.os.Process
import android.provider.Settings
import android.text.TextUtils
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.lukac.timerewards/enforcement"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasPermissions" -> result.success(hasPermissions())
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
            Settings.Secure.ENABLED_NOTIFICATION_LISTENERS
        ) ?: return false
        val splitter = TextUtils.SimpleStringSplitter(':')
        splitter.setString(enabled)
        while (splitter.hasNext()) {
            if (splitter.next().equals(expected, ignoreCase = true)) return true
        }
        return false
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
