import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/reward_ledger.dart';
import '../models/task.dart';

class StorageService {
  static const _kTasks = 'tasks_v1';
  static const _kLedger = 'ledger_v1';
  static const _kBlockedApps = 'blocked_apps_v1';

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
}
