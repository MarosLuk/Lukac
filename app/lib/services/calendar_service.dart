/// Stub for calendar / to-do integration.
///
/// Wire one of the following in a future iteration:
///   - Google Tasks / Calendar (googleapis + google_sign_in)
///   - Apple EventKit (device_calendar plugin)
///   - Todoist REST API
///   - Microsoft To Do via Graph API
///
/// The MVP uses the local task list only. Keeping this file as a marker
/// so the integration point is explicit.
abstract class CalendarSource {
  Future<List<ExternalTask>> fetchPending();
}

class ExternalTask {
  ExternalTask({
    required this.externalId,
    required this.title,
    required this.dueAt,
  });
  final String externalId;
  final String title;
  final DateTime dueAt;
}
