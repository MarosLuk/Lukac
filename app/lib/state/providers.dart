import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/reward_ledger.dart';
import '../models/task.dart';
import '../services/enforcement_service.dart';
import '../services/storage_service.dart';

// ---------------------------------------------------------------------------
// Services
// ---------------------------------------------------------------------------

final storageServiceProvider = Provider<StorageService>((ref) {
  return StorageService();
});

final enforcementServiceProvider = Provider<EnforcementService>((ref) {
  return EnforcementService();
});

// ---------------------------------------------------------------------------
// Tasks
// ---------------------------------------------------------------------------

class TasksNotifier extends AsyncNotifier<List<TaskItem>> {
  @override
  Future<List<TaskItem>> build() async {
    final storage = ref.read(storageServiceProvider);
    return storage.loadTasks();
  }

  Future<void> add(String title, int rewardMinutes) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return;
    final current = state.valueOrNull ?? const <TaskItem>[];
    final next = [
      ...current,
      TaskItem(title: trimmed, rewardMinutes: rewardMinutes),
    ];
    state = AsyncData(next);
    await ref.read(storageServiceProvider).saveTasks(next);
  }

  /// Idempotent: only credits the reward the first time a task transitions
  /// from pending to completed.
  Future<void> complete(String id) async {
    final current = state.valueOrNull ?? const <TaskItem>[];
    final idx = current.indexWhere((t) => t.id == id);
    if (idx < 0) return;
    final existing = current[idx];
    if (existing.completed) return;
    final updated = existing.copyWith(
      completed: true,
      completedAt: DateTime.now(),
    );
    final next = [...current]..[idx] = updated;
    state = AsyncData(next);
    final storage = ref.read(storageServiceProvider);
    await storage.saveTasks(next);
    // Credit the reward on the ledger.
    await ref
        .read(ledgerProvider.notifier)
        .credit(Duration(minutes: updated.rewardMinutes));
  }

  Future<void> delete(String id) async {
    final current = state.valueOrNull ?? const <TaskItem>[];
    final next = current.where((t) => t.id != id).toList();
    state = AsyncData(next);
    await ref.read(storageServiceProvider).saveTasks(next);
  }
}

final tasksProvider =
    AsyncNotifierProvider<TasksNotifier, List<TaskItem>>(TasksNotifier.new);

final pendingTasksProvider = Provider<List<TaskItem>>((ref) {
  final tasks = ref.watch(tasksProvider).valueOrNull ?? const <TaskItem>[];
  return tasks.where((t) => !t.completed).toList(growable: false);
});

// ---------------------------------------------------------------------------
// Ledger
// ---------------------------------------------------------------------------

class LedgerNotifier extends AsyncNotifier<RewardLedger> {
  Timer? _ticker;

  @override
  Future<RewardLedger> build() async {
    final storage = ref.read(storageServiceProvider);
    final loaded = await storage.loadLedger();
    _startTicker();
    ref.onDispose(() {
      _ticker?.cancel();
      _ticker = null;
    });
    return loaded;
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final ledger = state.valueOrNull;
      if (ledger == null) return;
      final hasActiveLift = ledger.shieldLiftedUntil != null;
      if (!hasActiveLift) return;
      if (!ledger.isShieldLifted) {
        // Lift just expired: clear the window, re-apply the shield, rebuild.
        final cleared = ledger.copyWith(clearShieldLiftedUntil: true);
        state = AsyncData(cleared);
        unawaited(ref.read(storageServiceProvider).saveLedger(cleared));
        unawaited(_syncShield());
      } else {
        // Still in the unlock window — tick the countdown UI by re-emitting
        // the same value so watchers rebuild.
        state = AsyncData(ledger);
      }
    });
  }

  Future<void> credit(Duration amount) async {
    final seconds = amount.inSeconds;
    if (seconds <= 0) return;
    final current = state.valueOrNull ?? RewardLedger();
    final next = current.copyWith(
      balanceSeconds: current.balanceSeconds + seconds,
    );
    state = AsyncData(next);
    await ref.read(storageServiceProvider).saveLedger(next);
    await _syncShield();
  }

  /// Per-duration gate: only spends as much as is available. No-op if the
  /// balance is zero or the requested amount is non-positive.
  Future<void> spend(Duration amount) async {
    final wantSeconds = amount.inSeconds;
    if (wantSeconds <= 0) return;
    final current = state.valueOrNull ?? RewardLedger();
    final available = current.balanceSeconds;
    final spend = wantSeconds > available ? available : wantSeconds;
    if (spend == 0) return;
    final until =
        (current.shieldLiftedUntil != null && current.isShieldLifted
                ? current.shieldLiftedUntil!
                : DateTime.now())
            .add(Duration(seconds: spend));
    final next = current.copyWith(
      balanceSeconds: available - spend,
      shieldLiftedUntil: until,
    );
    state = AsyncData(next);
    await ref.read(storageServiceProvider).saveLedger(next);
    await _syncShield();
  }

  Future<void> clearExpiredLift() async {
    final current = state.valueOrNull;
    if (current == null) return;
    if (current.shieldLiftedUntil == null) return;
    if (current.isShieldLifted) return;
    final next = current.copyWith(clearShieldLiftedUntil: true);
    state = AsyncData(next);
    await ref.read(storageServiceProvider).saveLedger(next);
    await _syncShield();
  }

  Future<void> _syncShield() async {
    // Delegated to the shield sync helper so both ledger and blocked-apps
    // mutations go through the same platform code path.
    await _applyShield(
      ref.read(enforcementServiceProvider),
      ledger: state.valueOrNull ?? RewardLedger(),
      blockedApps: ref.read(blockedAppsProvider).valueOrNull ?? const [],
      allowedApps: ref.read(allowedAppsProvider).valueOrNull ?? const [],
    );
  }
}

final ledgerProvider =
    AsyncNotifierProvider<LedgerNotifier, RewardLedger>(LedgerNotifier.new);

// ---------------------------------------------------------------------------
// Blocked apps
// ---------------------------------------------------------------------------

class BlockedAppsNotifier extends AsyncNotifier<List<String>> {
  @override
  Future<List<String>> build() async {
    final storage = ref.read(storageServiceProvider);
    return storage.loadBlockedApps();
  }

  Future<void> setPackages(List<String> packages) async {
    final next = List<String>.unmodifiable(packages);
    state = AsyncData(next);
    await ref.read(storageServiceProvider).saveBlockedApps(next);
    await _applyShield(
      ref.read(enforcementServiceProvider),
      ledger: ref.read(ledgerProvider).valueOrNull ?? RewardLedger(),
      blockedApps: next,
      allowedApps: ref.read(allowedAppsProvider).valueOrNull ?? const [],
    );
  }
}

final blockedAppsProvider =
    AsyncNotifierProvider<BlockedAppsNotifier, List<String>>(
        BlockedAppsNotifier.new);

// ---------------------------------------------------------------------------
// Allowed apps (always-allowed even while the shield is active)
// ---------------------------------------------------------------------------

class AllowedAppsNotifier extends AsyncNotifier<List<String>> {
  @override
  Future<List<String>> build() async {
    final storage = ref.read(storageServiceProvider);
    return storage.loadAllowedApps();
  }

  Future<void> setPackages(List<String> packages) async {
    final next = List<String>.unmodifiable(packages);
    state = AsyncData(next);
    await ref.read(storageServiceProvider).saveAllowedApps(next);
    final enforcement = ref.read(enforcementServiceProvider);
    // Push the allow-list to the native layer first so it is in place by the
    // time the shield re-applies (Android AccessibilityService reads it live).
    try {
      await enforcement.setAllowList(packages: next);
    } catch (_) {
      // Native side may not be wired (desktop / tests). Ignore.
    }
    await _applyShield(
      enforcement,
      ledger: ref.read(ledgerProvider).valueOrNull ?? RewardLedger(),
      blockedApps: ref.read(blockedAppsProvider).valueOrNull ?? const [],
      allowedApps: next,
    );
  }
}

final allowedAppsProvider =
    AsyncNotifierProvider<AllowedAppsNotifier, List<String>>(
        AllowedAppsNotifier.new);

/// Android-only helper that returns a small set of canonical "essential"
/// apps (dialer, SMS, maps, etc.) that a user would typically want to
/// always allow. On iOS it returns an empty list because FamilyControls
/// already guards system apps.
final essentialAppsProvider = FutureProvider<List<InstalledApp>>((ref) async {
  if (!Platform.isAndroid) return const [];
  return ref.read(enforcementServiceProvider).listEssentialApps();
});

// ---------------------------------------------------------------------------
// Shield sync
// ---------------------------------------------------------------------------

Future<void> _applyShield(
  EnforcementService enforcement, {
  required RewardLedger ledger,
  required List<String> blockedApps,
  List<String> allowedApps = const [],
}) async {
  try {
    if (ledger.isShieldLifted) {
      await enforcement.clearShield();
      return;
    }
    // iOS ignores the `packages` / `allowed` lists at the native layer —
    // the FamilyActivityPicker selections are held by the bridge, so we
    // always forward an applyShield call. On Android we only apply if the
    // user has chosen at least one package, but we forward the allow-list
    // either way so the accessibility service has it on hand.
    if (Platform.isIOS) {
      await enforcement.applyShield(
        packages: blockedApps,
        allowedPackages: allowedApps,
      );
    } else if (blockedApps.isEmpty) {
      await enforcement.clearShield();
    } else {
      await enforcement.applyShield(
        packages: blockedApps,
        allowedPackages: allowedApps,
      );
    }
  } catch (_) {
    // Native side may not be wired (e.g. running on desktop). Ignore.
  }
}

/// Side-effect provider: watches ledger + blocked apps and keeps the native
/// shield in sync. Returning `true` lets widgets `ref.watch` it cheaply to
/// ensure it is kept alive for the lifetime of the ProviderScope.
final shieldSyncProvider = Provider<bool>((ref) {
  ref.listen<AsyncValue<RewardLedger>>(ledgerProvider, (prev, next) {
    final ledger = next.valueOrNull;
    if (ledger == null) return;
    final blocked =
        ref.read(blockedAppsProvider).valueOrNull ?? const <String>[];
    final allowed =
        ref.read(allowedAppsProvider).valueOrNull ?? const <String>[];
    unawaited(_applyShield(
      ref.read(enforcementServiceProvider),
      ledger: ledger,
      blockedApps: blocked,
      allowedApps: allowed,
    ));
  });
  ref.listen<AsyncValue<List<String>>>(blockedAppsProvider, (prev, next) {
    final blocked = next.valueOrNull;
    if (blocked == null) return;
    final ledger = ref.read(ledgerProvider).valueOrNull ?? RewardLedger();
    final allowed =
        ref.read(allowedAppsProvider).valueOrNull ?? const <String>[];
    unawaited(_applyShield(
      ref.read(enforcementServiceProvider),
      ledger: ledger,
      blockedApps: blocked,
      allowedApps: allowed,
    ));
  });
  ref.listen<AsyncValue<List<String>>>(allowedAppsProvider, (prev, next) {
    final allowed = next.valueOrNull;
    if (allowed == null) return;
    final ledger = ref.read(ledgerProvider).valueOrNull ?? RewardLedger();
    final blocked =
        ref.read(blockedAppsProvider).valueOrNull ?? const <String>[];
    unawaited(_applyShield(
      ref.read(enforcementServiceProvider),
      ledger: ledger,
      blockedApps: blocked,
      allowedApps: allowed,
    ));
  });
  return true;
});

// ---------------------------------------------------------------------------
// Permissions & installed apps
// ---------------------------------------------------------------------------

final permissionStatusProvider = FutureProvider<bool>((ref) async {
  try {
    return await ref.read(enforcementServiceProvider).hasPermissions();
  } catch (_) {
    return false;
  }
});

/// Whether the OS-level notification-listener access is granted. On iOS
/// this is always `false` — see [EnforcementService.hasNotificationAccess].
/// Callers should `ref.invalidate` this provider after returning from the
/// Settings screen to re-check.
final notificationAccessProvider = FutureProvider<bool>((ref) async {
  try {
    return await ref.read(enforcementServiceProvider).hasNotificationAccess();
  } catch (_) {
    return false;
  }
});

final installedAppsProvider = FutureProvider<List<InstalledApp>>((ref) async {
  if (!Platform.isAndroid) return const [];
  return ref.read(enforcementServiceProvider).listInstalledApps();
});
