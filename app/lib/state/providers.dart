import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/external_task.dart';
import '../models/reward_ledger.dart';
import '../models/task.dart';
import '../services/enforcement_service.dart';
import '../services/sources/ics_source.dart';
import '../services/sources/task_source.dart';
import '../services/sources/todoist_source.dart';
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

// ---------------------------------------------------------------------------
// Task-source integrations
// ---------------------------------------------------------------------------

/// The static registry of source *types* the user can connect. Each
/// descriptor knows its id, display metadata, required config fields and
/// how to build a stateless [TaskSource] instance from a stored
/// [TaskSourceConfig].
///
/// This is where OAuth providers (Google Tasks, Microsoft To Do, Notion,
/// Trello, …) will plug in later: they add a descriptor with an auth-flow
/// button in place of (or alongside) `fields`, and the
/// [ConnectedSourcesNotifier.connect] path stays the same — the resulting
/// tokens just land in [TaskSourceConfig.fields] the same way.
final availableSourceTypesProvider = Provider<List<SourceDescriptor>>((ref) {
  return [
    SourceDescriptor(
      id: 'ics',
      displayName: 'ICS URL',
      description:
          'Any public iCalendar .ics feed. Future events become tasks.',
      icon: Icons.event_outlined,
      fields: const [
        SourceFieldSpec(
          key: 'url',
          label: 'Feed URL',
          hint: 'https://example.com/calendar.ics',
        ),
      ],
      buildFromConfig: (cfg) => IcsSource(url: cfg.fields['url'] ?? ''),
    ),
    SourceDescriptor(
      id: 'todoist',
      displayName: 'Todoist',
      description: 'Pull pending Todoist tasks via a personal API token.',
      icon: Icons.checklist_outlined,
      fields: const [
        SourceFieldSpec(
          key: 'token',
          label: 'API token',
          hint: 'Todoist → Settings → Integrations → Developer',
          obscured: true,
        ),
      ],
      buildFromConfig: (cfg) =>
          TodoistSource(token: cfg.fields['token'] ?? ''),
    ),
  ];
});

/// Connected-source configurations. Persisted via [StorageService] under
/// `sources_v1`. Mutations are routed through this notifier so the
/// [externalTasksProvider] can listen and refresh on connect/disconnect.
class ConnectedSourcesNotifier extends AsyncNotifier<List<TaskSourceConfig>> {
  @override
  Future<List<TaskSourceConfig>> build() async {
    final storage = ref.read(storageServiceProvider);
    return storage.loadSources();
  }

  Future<void> _persist(List<TaskSourceConfig> next) async {
    state = AsyncData(next);
    await ref.read(storageServiceProvider).saveSources(next);
  }

  Future<void> connect(String sourceId, Map<String, String> fields) async {
    final current = state.valueOrNull ?? const <TaskSourceConfig>[];
    final trimmed = <String, String>{
      for (final entry in fields.entries) entry.key: entry.value.trim(),
    };
    final existingIdx = current.indexWhere((c) => c.sourceId == sourceId);
    final cfg = TaskSourceConfig(
      sourceId: sourceId,
      fields: trimmed,
      enabled: true,
    );
    final next = [...current];
    if (existingIdx >= 0) {
      next[existingIdx] = cfg.copyWith(
        lastSyncAt: current[existingIdx].lastSyncAt,
      );
    } else {
      next.add(cfg);
    }
    await _persist(next);
    // Kick off an initial sync; errors are swallowed inside refresh().
    await ref.read(externalTasksProvider.notifier).refresh();
  }

  Future<void> disconnect(String sourceId) async {
    final current = state.valueOrNull ?? const <TaskSourceConfig>[];
    final next = current.where((c) => c.sourceId != sourceId).toList();
    await _persist(next);
    await ref.read(externalTasksProvider.notifier).refresh();
  }

  Future<void> setEnabled(String sourceId, bool enabled) async {
    final current = state.valueOrNull ?? const <TaskSourceConfig>[];
    final idx = current.indexWhere((c) => c.sourceId == sourceId);
    if (idx < 0) return;
    final next = [...current]
      ..[idx] = current[idx].copyWith(enabled: enabled);
    await _persist(next);
    await ref.read(externalTasksProvider.notifier).refresh();
  }

  /// Internal: bump the `lastSyncAt` stamp for a given source after a
  /// successful fetch. Does not re-trigger a refresh.
  Future<void> markSynced(String sourceId, DateTime at) async {
    final current = state.valueOrNull ?? const <TaskSourceConfig>[];
    final idx = current.indexWhere((c) => c.sourceId == sourceId);
    if (idx < 0) return;
    final next = [...current]..[idx] = current[idx].copyWith(lastSyncAt: at);
    state = AsyncData(next);
    await ref.read(storageServiceProvider).saveSources(next);
  }
}

final connectedSourcesProvider =
    AsyncNotifierProvider<ConnectedSourcesNotifier, List<TaskSourceConfig>>(
  ConnectedSourcesNotifier.new,
);

/// The union of external tasks across all connected, enabled sources.
///
/// On build, loads the last persisted union so the Tasks tab is populated
/// offline. [refresh] iterates enabled configs, fetches each source,
/// swallows per-source errors, persists the union, and updates state.
class ExternalTasksNotifier extends AsyncNotifier<List<ExternalTask>> {
  @override
  Future<List<ExternalTask>> build() async {
    final storage = ref.read(storageServiceProvider);
    return storage.loadExternalTasks();
  }

  Future<void> refresh() async {
    final configs =
        ref.read(connectedSourcesProvider).valueOrNull ?? const [];
    final descriptors = ref.read(availableSourceTypesProvider);
    final descriptorById = {for (final d in descriptors) d.id: d};

    final combined = <ExternalTask>[];
    for (final cfg in configs) {
      if (!cfg.enabled) continue;
      final descriptor = descriptorById[cfg.sourceId];
      if (descriptor == null) continue;
      try {
        final source = descriptor.buildFromConfig(cfg);
        final tasks = await source.fetchPending();
        combined.addAll(tasks);
        await ref
            .read(connectedSourcesProvider.notifier)
            .markSynced(cfg.sourceId, DateTime.now());
      } catch (e, st) {
        // Per-source errors: log and skip. A bad ICS URL should not take
        // out a working Todoist sync.
        debugPrint('Source ${cfg.sourceId} sync failed: $e\n$st');
      }
    }

    // Drop items already accepted as local tasks (locked by title match as
    // a best-effort: there is no back-link from TaskItem → externalId in
    // MVP). A stricter match will land when we add that field.
    // Keep externalId uniqueness across the union (sourceId + externalId).
    final deduped = <String, ExternalTask>{};
    for (final t in combined) {
      deduped['${t.sourceId}::${t.externalId}'] = t;
    }
    final result = deduped.values.toList()
      ..sort((a, b) {
        final ad = a.dueAt;
        final bd = b.dueAt;
        if (ad == null && bd == null) return 0;
        if (ad == null) return 1;
        if (bd == null) return -1;
        return ad.compareTo(bd);
      });

    state = AsyncData(result);
    await ref.read(storageServiceProvider).saveExternalTasks(result);
  }

  /// Removes a single external task from the in-memory + persisted union.
  /// Called after the user "accepts" an external task into the local list
  /// so it does not reappear on the next Tasks-tab build.
  Future<void> dismiss(String sourceId, String externalId) async {
    final current = state.valueOrNull ?? const <ExternalTask>[];
    final next = current
        .where((t) => !(t.sourceId == sourceId && t.externalId == externalId))
        .toList();
    state = AsyncData(next);
    await ref.read(storageServiceProvider).saveExternalTasks(next);
  }
}

final externalTasksProvider =
    AsyncNotifierProvider<ExternalTasksNotifier, List<ExternalTask>>(
  ExternalTasksNotifier.new,
);
