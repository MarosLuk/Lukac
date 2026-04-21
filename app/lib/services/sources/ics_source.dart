import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../models/external_task.dart';
import 'task_source.dart';

/// Reads any public iCalendar (.ics) feed and surfaces each future-dated
/// `VEVENT` as an [ExternalTask] with DTSTART as its due time.
///
/// The parser is intentionally minimal — we do not implement recurrence
/// expansion, time-zone lookup, or folded-line handling beyond unfolding
/// simple `\r\n[ \t]` continuations. That is enough for the common case of
/// publishing a static agenda (university timetable, a team's shared
/// events) which is where this source earns its keep.
class IcsSource implements TaskSource {
  IcsSource({required this.url, http.Client? client})
      : _client = client ?? http.Client();

  final String url;
  final http.Client _client;

  @override
  String get id => 'ics';

  @override
  String get displayName => 'ICS URL';

  @override
  String get description =>
      'Any public iCalendar .ics feed. Future events become tasks.';

  @override
  IconData get icon => Icons.event_outlined;

  @override
  Future<List<ExternalTask>> fetchPending({DateTime? horizonEnd}) async {
    final now = DateTime.now();
    final end = horizonEnd ?? now.add(const Duration(days: 14));

    final resp = await _client
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 10));
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('ICS fetch failed: HTTP ${resp.statusCode}');
    }

    return parseIcs(resp.body, now: now, horizonEnd: end);
  }

  /// Visible for tests: pure parsing.
  static List<ExternalTask> parseIcs(
    String body, {
    required DateTime now,
    required DateTime horizonEnd,
  }) {
    // Unfold: RFC 5545 line continuation is CRLF + (space|tab).
    final unfolded = body
        .replaceAll('\r\n', '\n')
        .replaceAll(RegExp(r'\n[ \t]'), '');

    final lines = unfolded.split('\n');
    final results = <ExternalTask>[];
    var inEvent = false;
    String? uid;
    String? summary;
    DateTime? dtstart;

    for (final raw in lines) {
      final line = raw.trimRight();
      if (line == 'BEGIN:VEVENT') {
        inEvent = true;
        uid = null;
        summary = null;
        dtstart = null;
        continue;
      }
      if (line == 'END:VEVENT') {
        if (inEvent && dtstart != null) {
          final title = summary ?? '(untitled)';
          final id = uid ?? '$title@${dtstart.toIso8601String()}';
          if (dtstart.isAfter(now) && dtstart.isBefore(horizonEnd)) {
            results.add(ExternalTask(
              externalId: id,
              sourceId: 'ics',
              title: title,
              dueAt: dtstart,
            ));
          }
        }
        inEvent = false;
        continue;
      }
      if (!inEvent) continue;

      // Split "NAME[;PARAM=VAL]:VALUE". The property name/params are before
      // the first `:`, but `:` can appear in values (e.g. URL) so take the
      // first split only.
      final colon = line.indexOf(':');
      if (colon < 0) continue;
      final head = line.substring(0, colon);
      final value = line.substring(colon + 1);
      final semi = head.indexOf(';');
      final name = (semi < 0 ? head : head.substring(0, semi)).toUpperCase();

      switch (name) {
        case 'UID':
          uid = value;
          break;
        case 'SUMMARY':
          summary = _unescapeText(value);
          break;
        case 'DTSTART':
          dtstart = _parseIcsDate(value);
          break;
      }
    }
    return results;
  }

  static String _unescapeText(String v) => v
      .replaceAll(r'\n', '\n')
      .replaceAll(r'\N', '\n')
      .replaceAll(r'\,', ',')
      .replaceAll(r'\;', ';')
      .replaceAll(r'\\', r'\');

  /// Parses the small subset of RFC 5545 dates we care about:
  ///   - `YYYYMMDDTHHMMSSZ` (UTC)
  ///   - `YYYYMMDDTHHMMSS`  (floating local)
  ///   - `YYYYMMDD`         (all-day; treated as 00:00 local)
  static DateTime? _parseIcsDate(String value) {
    final v = value.trim();
    if (v.length >= 15 && v[8] == 'T') {
      final y = int.tryParse(v.substring(0, 4));
      final mo = int.tryParse(v.substring(4, 6));
      final d = int.tryParse(v.substring(6, 8));
      final h = int.tryParse(v.substring(9, 11));
      final mi = int.tryParse(v.substring(11, 13));
      final s = int.tryParse(v.substring(13, 15));
      if ([y, mo, d, h, mi, s].any((x) => x == null)) return null;
      final isUtc = v.endsWith('Z');
      final dt = isUtc
          ? DateTime.utc(y!, mo!, d!, h!, mi!, s!)
          : DateTime(y!, mo!, d!, h!, mi!, s!);
      return isUtc ? dt.toLocal() : dt;
    }
    if (v.length == 8) {
      final y = int.tryParse(v.substring(0, 4));
      final mo = int.tryParse(v.substring(4, 6));
      final d = int.tryParse(v.substring(6, 8));
      if (y == null || mo == null || d == null) return null;
      return DateTime(y, mo, d);
    }
    return null;
  }
}
