import 'package:flutter/material.dart';

import '../../models/external_task.dart';

/// Contract every task-source adapter implements.
///
/// Implementations are **stateless**: the per-connection configuration
/// (tokens, URLs, etc.) lives in a [TaskSourceConfig] and is handed to the
/// adapter's constructor by the [SourceDescriptor] factory.
///
/// OAuth-based sources (Google, Microsoft, Notion, ...) will plug in here
/// too — they just need a richer descriptor that launches an auth flow in
/// place of the plain-form bottom sheet.
abstract class TaskSource {
  /// Stable id (e.g. `"ics"`, `"todoist"`). Must match [ExternalTask.sourceId].
  String get id;

  String get displayName;

  /// One short sentence shown next to the source in the Sources screen.
  String get description;

  IconData get icon;

  /// Fetches currently-pending external tasks. Implementations should:
  ///   - drop tasks due before `DateTime.now()`
  ///   - drop tasks due after [horizonEnd] (default: now + 14 days)
  ///   - return an empty list on a benign empty feed
  ///   - throw on auth/transport errors so the provider can log + skip
  Future<List<ExternalTask>> fetchPending({DateTime? horizonEnd});
}

/// The persistent configuration for one connected source.
///
/// `fields` holds whatever key/value pairs the descriptor declared in its
/// [SourceFieldSpec] list (e.g. `{"url": "..."}` for ICS,
/// `{"token": "..."}` for Todoist).
///
/// NOTE: tokens are stored in SharedPreferences for MVP; see follow-ups in
/// `FEATURES.md` for migrating to `flutter_secure_storage`.
class TaskSourceConfig {
  const TaskSourceConfig({
    required this.sourceId,
    required this.fields,
    this.enabled = true,
    this.lastSyncAt,
  });

  final String sourceId;
  final Map<String, String> fields;
  final bool enabled;
  final DateTime? lastSyncAt;

  TaskSourceConfig copyWith({
    Map<String, String>? fields,
    bool? enabled,
    DateTime? lastSyncAt,
    bool clearLastSyncAt = false,
  }) =>
      TaskSourceConfig(
        sourceId: sourceId,
        fields: fields ?? this.fields,
        enabled: enabled ?? this.enabled,
        lastSyncAt:
            clearLastSyncAt ? null : (lastSyncAt ?? this.lastSyncAt),
      );

  Map<String, dynamic> toJson() => {
        'sourceId': sourceId,
        'fields': fields,
        'enabled': enabled,
        'lastSyncAt': lastSyncAt?.toIso8601String(),
      };

  factory TaskSourceConfig.fromJson(Map<String, dynamic> json) =>
      TaskSourceConfig(
        sourceId: json['sourceId'] as String,
        fields: (json['fields'] as Map<dynamic, dynamic>? ?? const {})
            .map((k, v) => MapEntry(k.toString(), v?.toString() ?? '')),
        enabled: json['enabled'] as bool? ?? true,
        lastSyncAt: json['lastSyncAt'] == null
            ? null
            : DateTime.tryParse(json['lastSyncAt'] as String),
      );
}

/// Describes one source *type* the user can connect. Held in a registry,
/// one entry per supported provider. Knows how to render its config form
/// and how to build a live [TaskSource] instance from a [TaskSourceConfig].
class SourceDescriptor {
  const SourceDescriptor({
    required this.id,
    required this.displayName,
    required this.description,
    required this.icon,
    required this.fields,
    required this.buildFromConfig,
  });

  final String id;
  final String displayName;
  final String description;
  final IconData icon;
  final List<SourceFieldSpec> fields;
  final TaskSource Function(TaskSourceConfig) buildFromConfig;
}

/// One configurable field in a descriptor form. Rendered as a `TextField`
/// on the Sources screen; [obscured] secrets render with `obscureText: true`.
class SourceFieldSpec {
  const SourceFieldSpec({
    required this.key,
    required this.label,
    this.hint = '',
    this.obscured = false,
  });

  final String key;
  final String label;
  final String hint;
  final bool obscured;
}
