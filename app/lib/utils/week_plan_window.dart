import '../models/note.dart';

/// Inclusive window: start of [now]'s calendar day through end of the upcoming Saturday
/// (including today when today is Saturday).
class WeekPlanWindow {
  const WeekPlanWindow({required this.start, required this.end});

  final DateTime start;
  final DateTime end;

  /// Human-readable range for AI prompts, e.g. "22 Mar 2026 – 28 Mar 2026".
  String describe() {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    String fmt(DateTime d) =>
        '${d.day} ${months[d.month - 1]} ${d.year}';
    return '${fmt(start)} – ${fmt(end)}';
  }
}

DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime _endOfDay(DateTime d) =>
    DateTime(d.year, d.month, d.day, 23, 59, 59, 999);

/// Monday = 1 … Sunday = 7 (Dart [DateTime.weekday]).
WeekPlanWindow thisWeekThroughNextSaturday(DateTime now) {
  final start = _startOfDay(now);
  const int saturday = 6;
  int diff = saturday - start.weekday;
  if (diff < 0) {
    diff += 7;
  }
  final satDate = start.add(Duration(days: diff));
  final end = _endOfDay(satDate);
  return WeekPlanWindow(start: start, end: end);
}

bool _betweenInclusive(DateTime t, DateTime start, DateTime end) =>
    !t.isBefore(start) && !t.isAfter(end);

/// Heuristic: user is asking about plans/tasks for the current rolling week window.
bool looksLikeWeekPlanQuestion(String query) {
  final s = query.toLowerCase().trim();
  if (s.isEmpty) return false;
  if (s.contains('last week')) return false;

  if (s.contains('this week')) return true;
  if (s.contains('weekly plan') || s.contains('week plan')) return true;

  final mentionsWeek = s.contains('week') || s.contains('weekly');
  final mentionsPlan =
      s.contains('plan') || s.contains('schedule') || s.contains('calendar');
  if (mentionsWeek && mentionsPlan) return true;

  if (s.contains('my week') && (s.contains('plan') || s.contains('look'))) {
    return true;
  }

  return false;
}

/// Keeps notes that belong to [window]: reminders in range, or undated notes
/// created/updated on or after [window.start]. Drops reminders before today and
/// after [window.end].
List<Note> filterNotesForWeekPlan(List<Note> notes, WeekPlanWindow window) {
  final out = <Note>[];

  for (final n in notes) {
    final r = n.reminderTime;
    if (r != null) {
      if (_betweenInclusive(r, window.start, window.end)) {
        out.add(n);
      }
      continue;
    }

    final touchedAfterStart =
        !n.createdAt.isBefore(window.start) || !n.updatedAt.isBefore(window.start);
    if (touchedAfterStart) {
      out.add(n);
    }
  }

  return out;
}
