import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/external_task.dart';
import '../models/reward_ledger.dart';
import '../models/task.dart';
import 'sources/task_source.dart';

class StorageService {
  static const _kTasks = 'tasks_v1';
  static const _kLedger = 'ledger_v1';
  static const _kBlockedApps = 'blocked_apps_v1';
  static const _kAllowedApps = 'allowed_apps_v1';
  static const _kSources = 'sources_v1';
  static const _kExternalTasks = 'external_tasks_v1';

  Future<List<TaskItem>> loadTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kTasks);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => TaskItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveTasks(List<TaskItem> tasks) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kTasks,
      jsonEncode(tasks.map((t) => t.toJson()).toList()),
    );
  }

  Future<RewardLedger> loadLedger() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kLedger);
    if (raw == null) return RewardLedger();
    return RewardLedger.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> saveLedger(RewardLedger ledger) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLedger, jsonEncode(ledger.toJson()));
  }

  Future<List<String>> loadBlockedApps() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_kBlockedApps) ?? const [];
  }

  Future<void> saveBlockedApps(List<String> packages) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kBlockedApps, packages);
  }

  Future<List<String>> loadAllowedApps() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_kAllowedApps) ?? const [];
  }

  Future<void> saveAllowedApps(List<String> packages) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kAllowedApps, packages);
  }

  Future<List<TaskSourceConfig>> loadSources() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kSources);
    if (raw == null) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map<dynamic, dynamic>>()
          .map((m) => TaskSourceConfig.fromJson(m.cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveSources(List<TaskSourceConfig> sources) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kSources,
      jsonEncode(sources.map((s) => s.toJson()).toList()),
    );
  }

  /// Last fetched union of external tasks so the Tasks tab has something to
  /// render offline. Overwritten on every successful sync; per-source errors
  /// are swallowed by the provider so partial unions are normal.
  Future<List<ExternalTask>> loadExternalTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kExternalTasks);
    if (raw == null) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map<dynamic, dynamic>>()
          .map((m) => ExternalTask.fromJson(m.cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveExternalTasks(List<ExternalTask> tasks) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kExternalTasks,
      jsonEncode(tasks.map((t) => t.toJson()).toList()),
    );
  }
}
