import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../../models/external_task.dart';
import '../enforcement_service.dart';
import 'task_source.dart';

/// Reads upcoming events from every calendar already synced to the device
/// (Google Calendar, Outlook, Teams meetings via Outlook, Samsung, …) via
/// Android's [CalendarContract]. Each event instance becomes an
/// [ExternalTask] with DTSTART as its `dueAt`.
///
/// Requires the `READ_CALENDAR` runtime permission. The first [fetchPending]
/// call surfaces the standard Android permission dialog; subsequent calls
/// reuse the grant.
class DeviceCalendarSource implements TaskSource {
  DeviceCalendarSource({EnforcementService? service})
      : _service = service ?? EnforcementService();

  final EnforcementService _service;

  @override
  String get id => 'device_calendar';

  @override
  String get displayName => 'Device calendar';

  @override
  String get description =>
      'Reads upcoming events from Google, Outlook (incl. Teams meetings), '
      'Samsung and any other calendar synced to your phone.';

  @override
  IconData get icon => Icons.calendar_month_outlined;

  @override
  Future<List<ExternalTask>> fetchPending({DateTime? horizonEnd}) async {
    if (!Platform.isAndroid) return const [];

    final granted = await _service.hasCalendarAccess();
    if (!granted) {
      final ok = await _service.requestCalendarAccess();
      if (!ok) {
        throw Exception(
          'Calendar permission not granted. Enable it to sync events.',
        );
      }
    }

    final now = DateTime.now();
    final end = horizonEnd ?? now.add(const Duration(days: 14));
    final events = await _service.listCalendarEvents(from: now, to: end);

    final tasks = <ExternalTask>[];
    for (final e in events) {
      final rawTitle = (e['title'] as String?)?.trim() ?? '';
      final title = rawTitle.isEmpty ? '(untitled event)' : rawTitle;
      final beginMs = _readInt(e['beginMs']);
      final eventIdStr = e['eventId']?.toString() ?? '';
      if (eventIdStr.isEmpty) continue;
      tasks.add(
        ExternalTask(
          // Suffix with beginMs so recurring-event instances stay unique
          // (CalendarContract returns the same EVENT_ID for each occurrence).
          externalId: 'evt_${eventIdStr}_$beginMs',
          sourceId: id,
          title: title,
          dueAt: beginMs > 0
              ? DateTime.fromMillisecondsSinceEpoch(beginMs)
              : null,
        ),
      );
    }
    return tasks;
  }

  static int _readInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }
}
