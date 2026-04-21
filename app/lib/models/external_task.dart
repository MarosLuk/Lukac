/// A task pulled from an external source (ICS feed, Todoist, etc.).
///
/// External tasks do NOT credit the reward ledger on their own. The user
/// "accepts" them on the Tasks tab which creates a local [TaskItem] with
/// an explicit reward in minutes; the upstream system is left untouched.
class ExternalTask {
  const ExternalTask({
    required this.externalId,
    required this.sourceId,
    required this.title,
    this.dueAt,
    this.url,
  });

  /// Stable id as reported by the source. Must be unique within [sourceId].
  final String externalId;

  /// Matches [TaskSource.id] (e.g. `"ics"`, `"todoist"`).
  final String sourceId;

  final String title;

  /// For calendar events this is DTSTART. For to-do items it is the due
  /// date/time if any. `null` for tasks with no due date.
  final DateTime? dueAt;

  /// Optional deep-link back to the source (e.g. Todoist task URL).
  final String? url;

  Map<String, dynamic> toJson() => {
        'externalId': externalId,
        'sourceId': sourceId,
        'title': title,
        'dueAt': dueAt?.toIso8601String(),
        'url': url,
      };

  factory ExternalTask.fromJson(Map<String, dynamic> json) => ExternalTask(
        externalId: json['externalId'] as String,
        sourceId: json['sourceId'] as String,
        title: json['title'] as String,
        dueAt: json['dueAt'] == null
            ? null
            : DateTime.parse(json['dueAt'] as String),
        url: json['url'] as String?,
      );
}
