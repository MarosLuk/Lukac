import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../models/reward_ledger.dart';
import '../models/task.dart';
import '../services/enforcement_service.dart';
import '../services/storage_service.dart';

class AppState extends ChangeNotifier {
  AppState({StorageService? storage, EnforcementService? enforcement})
      : _storage = storage ?? StorageService(),
        _enforcement = enforcement ?? EnforcementService();

  final StorageService _storage;
  final EnforcementService _enforcement;

  List<TaskItem> _tasks = [];
  RewardLedger _ledger = RewardLedger();
  List<String> _blockedApps = [];
  Timer? _ticker;

  List<TaskItem> get tasks => List.unmodifiable(_tasks);
  List<TaskItem> get pendingTasks =>
      _tasks.where((t) => !t.completed).toList(growable: false);
  RewardLedger get ledger => _ledger;
  List<String> get blockedApps => List.unmodifiable(_blockedApps);
  EnforcementService get enforcement => _enforcement;

  Future<void> load() async {
    _tasks = await _storage.loadTasks();
    _ledger = await _storage.loadLedger();
    _blockedApps = await _storage.loadBlockedApps();
    _startTicker();
    await _syncShield();
    notifyListeners();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final hasActiveLift = _ledger.shieldLiftedUntil != null;
      if (!hasActiveLift) {
        // Nothing to tick — avoid spamming listeners every second.
        return;
      }
      if (!_ledger.isShieldLifted) {
        // Lift just expired: clear the window, re-apply the shield, notify.
        _ledger = _ledger.copyWith(clearShieldLiftedUntil: true);
        unawaited(_storage.saveLedger(_ledger));
        unawaited(_syncShield());
        notifyListeners();
      } else {
        // Still in the unlock window — tick the countdown UI.
        notifyListeners();
      }
    });
  }

  Future<void> addTask(String title, int rewardMinutes) async {
    _tasks = [
      ..._tasks,
      TaskItem(title: title, rewardMinutes: rewardMinutes),
    ];
    await _storage.saveTasks(_tasks);
    notifyListeners();
  }

  Future<void> completeTask(String id) async {
    final idx = _tasks.indexWhere((t) => t.id == id);
    if (idx < 0) return;
    final existing = _tasks[idx];
    // Idempotent: only credit when transitioning from pending -> completed.
    if (existing.completed) return;
    final updated = existing.copyWith(
      completed: true,
      completedAt: DateTime.now(),
    );
    _tasks = [..._tasks]..[idx] = updated;
    _ledger = _ledger.copyWith(
      balanceSeconds: _ledger.balanceSeconds + updated.rewardMinutes * 60,
    );
    await _storage.saveTasks(_tasks);
    await _storage.saveLedger(_ledger);
    notifyListeners();
  }

  Future<void> deleteTask(String id) async {
    _tasks = _tasks.where((t) => t.id != id).toList();
    await _storage.saveTasks(_tasks);
    notifyListeners();
  }

  Future<void> spendReward(Duration amount) async {
    final wantSeconds = amount.inSeconds;
    if (wantSeconds <= 0) return;
    final available = _ledger.balanceSeconds;
    final spend = wantSeconds > available ? available : wantSeconds;
    if (spend == 0) return;
    final until = (_ledger.shieldLiftedUntil != null && _ledger.isShieldLifted
            ? _ledger.shieldLiftedUntil!
            : DateTime.now())
        .add(Duration(seconds: spend));
    _ledger = _ledger.copyWith(
      balanceSeconds: available - spend,
      shieldLiftedUntil: until,
    );
    await _storage.saveLedger(_ledger);
    await _syncShield();
    notifyListeners();
  }

  Future<void> setBlockedApps(List<String> packages) async {
    _blockedApps = packages;
    await _storage.saveBlockedApps(_blockedApps);
    await _syncShield();
    notifyListeners();
  }

  Future<void> _syncShield() async {
    try {
      if (_ledger.isShieldLifted) {
        await _enforcement.clearShield();
        return;
      }
      // On iOS the `packages` list is ignored by the native layer — the
      // FamilyActivityPicker selection is stored by the system, so we
      // always forward an applyShield call. On Android we only apply if
      // the user has chosen at least one package.
      if (Platform.isIOS) {
        await _enforcement.applyShield(packages: _blockedApps);
      } else if (_blockedApps.isEmpty) {
        await _enforcement.clearShield();
      } else {
        await _enforcement.applyShield(packages: _blockedApps);
      }
    } catch (_) {
      // Native side may not be wired (e.g. running on desktop). Ignore.
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}

class AppStateScope extends InheritedNotifier<AppState> {
  const AppStateScope({
    super.key,
    required AppState state,
    required super.child,
  }) : super(notifier: state);

  static AppState of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<AppStateScope>();
    assert(scope != null, 'AppStateScope missing in widget tree');
    return scope!.notifier!;
  }
}
