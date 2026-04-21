import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../models/external_task.dart';
import 'task_source.dart';

/// Todoist adapter using the REST v2 API + a personal API token.
///
/// The token is retrieved from Todoist Settings → Integrations → Developer
/// and pasted into the config form. No OAuth in this pass; the same source
/// id (`todoist`) is what a future OAuth flow would write back into storage
/// so no data migration is needed when that lands.
class TodoistSource implements TaskSource {
  TodoistSource({required this.token, http.Client? client})
      : _client = client ?? http.Client();

  final String token;
  final http.Client _client;

  static final Uri _tasksUri =
      Uri.parse('https://api.todoist.com/rest/v2/tasks');

  @override
  String get id => 'todoist';

  @override
  String get displayName => 'Todoist';

  @override
  String get description =>
      'Pull pending Todoist tasks via a personal API token.';

  @override
  IconData get icon => Icons.checklist_outlined;

  @override
  Future<List<ExternalTask>> fetchPending({DateTime? horizonEnd}) async {
    final resp = await _client.get(
      _tasksUri,
      headers: {'Authorization': 'Bearer $token'},
    ).timeout(const Duration(seconds: 10));

    if (resp.statusCode == 401 || resp.statusCode == 403) {
      throw Exception('Todoist auth failed (${resp.statusCode})');
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('Todoist fetch failed: HTTP ${resp.statusCode}');
    }

    final decoded = jsonDecode(resp.body);
    if (decoded is! List) return const [];

    final now = DateTime.now();
    final end = horizonEnd;
    final results = <ExternalTask>[];
    for (final item in decoded) {
      if (item is! Map<String, dynamic>) continue;
      // REST v2 `/tasks` returns only active tasks, but be defensive.
      final isCompleted = item['is_completed'] as bool? ??
          item['completed'] as bool? ??
          false;
      if (isCompleted) continue;

      final id = item['id']?.toString();
      final content = item['content'] as String?;
      if (id == null || content == null || content.trim().isEmpty) continue;

      DateTime? due;
      final dueMap = item['due'];
      if (dueMap is Map<String, dynamic>) {
        final dt = dueMap['datetime'] as String?;
        final d = dueMap['date'] as String?;
        if (dt != null) {
          due = DateTime.tryParse(dt)?.toLocal();
        } else if (d != null) {
          due = DateTime.tryParse(d);
        }
      }

      // If a due date exists and is outside the window, skip. Tasks with no
      // due date are always kept — Todoist's "Inbox" is a valid surface.
      if (due != null) {
        if (due.isBefore(now.subtract(const Duration(days: 1)))) continue;
        if (end != null && due.isAfter(end)) continue;
      }

      results.add(ExternalTask(
        externalId: id,
        sourceId: 'todoist',
        title: content,
        dueAt: due,
        url: item['url'] as String?,
      ));
    }
    return results;
  }
}
