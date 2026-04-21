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

  /// Android-only: returns a small set of canonical "essential" apps
  /// (dialer, SMS, maps, etc.) resolved via default intents. iOS returns
  /// an empty list because FamilyControls guards system apps itself.
  Future<List<InstalledApp>> listEssentialApps() async {
    if (!Platform.isAndroid) return const [];
    final result =
        await _channel.invokeMethod<List<dynamic>>('listEssentialApps');
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

  /// iOS-only: opens the FamilyActivityPicker to choose the always-allowed
  /// selection. The selection is stored independently on the native side
  /// and subtracted from the shielded selection when the shield applies.
  Future<bool> pickAllowedAppsNative() async {
    if (!Platform.isIOS) return false;
    final ok = await _channel.invokeMethod<bool>('pickAllowedApps');
    return ok ?? false;
  }

  /// Apply the shield. On Android the [packages] list is used. On iOS the
  /// selection from [pickAppsNative] is used and [packages] is ignored.
  ///
  /// [allowedPackages] is forwarded so the native layer can compute the
  /// effective shield (Android skips these packages in the accessibility
  /// service; iOS subtracts the allowed selection from the shielded one).
  Future<void> applyShield({
    required List<String> packages,
    List<String> allowedPackages = const [],
  }) async {
    await _channel.invokeMethod('applyShield', {
      'packages': packages,
      'allowed': allowedPackages,
    });
  }

  Future<void> clearShield() async {
    await _channel.invokeMethod('clearShield');
  }

  /// Pushes the allow-list down to the native layer without touching the
  /// shielded selection. Used to keep the AccessibilityService prefs and
  /// the iOS `allowedSelection` in sync even when the shield is off.
  Future<void> setAllowList({required List<String> packages}) async {
    await _channel.invokeMethod('setAllowList', {'packages': packages});
  }
}

class InstalledApp {
  InstalledApp({required this.packageName, required this.label});
  final String packageName;
  final String label;
}
