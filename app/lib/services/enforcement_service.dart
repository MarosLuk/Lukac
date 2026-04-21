import 'dart:io';

import 'package:flutter/services.dart';

/// Bridge to the platform-specific app-blocking layer.
///
/// Android: backed by AccessibilityService + UsageStats.
/// iOS: backed by FamilyControls / ManagedSettings (requires entitlement).
class EnforcementService {
  static const _channel = MethodChannel('com.lukac.timerewards/enforcement');

  Future<bool> requestPermissions() async {
    final result = await _channel.invokeMethod<bool>('requestPermissions');
    return result ?? false;
  }

  Future<bool> hasPermissions() async {
    final result = await _channel.invokeMethod<bool>('hasPermissions');
    return result ?? false;
  }

  /// On Android, returns installed user-app packages.
  /// On iOS, returns an empty list — the user picks via [pickAppsNative].
  Future<List<InstalledApp>> listInstalledApps() async {
    if (!Platform.isAndroid) return const [];
    final result =
        await _channel.invokeMethod<List<dynamic>>('listInstalledApps');
    if (result == null) return const [];
    return result
        .cast<Map<dynamic, dynamic>>()
        .map((m) => InstalledApp(
              packageName: m['packageName'] as String,
              label: m['label'] as String? ?? m['packageName'] as String,
            ))
        .toList();
  }

  /// iOS-only: opens the FamilyActivityPicker. Returns true if user saved a
  /// selection. The selection is held by the native layer.
  Future<bool> pickAppsNative() async {
    if (!Platform.isIOS) return false;
    final ok = await _channel.invokeMethod<bool>('pickApps');
    return ok ?? false;
  }

  /// Apply the shield. On Android the [packages] list is used. On iOS the
  /// selection from [pickAppsNative] is used and [packages] is ignored.
  Future<void> applyShield({required List<String> packages}) async {
    await _channel.invokeMethod('applyShield', {'packages': packages});
  }

  Future<void> clearShield() async {
    await _channel.invokeMethod('clearShield');
  }
}

class InstalledApp {
  InstalledApp({required this.packageName, required this.label});
  final String packageName;
  final String label;
}
