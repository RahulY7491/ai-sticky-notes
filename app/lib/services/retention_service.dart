import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:timezone/timezone.dart' as tz;

import '../models/note.dart';
import 'security_service.dart';

/// Drives daily and weekly re-engagement notifications.
///
/// Every time the app opens (or a note is saved) we reschedule
/// the next daily and weekly notification with fresh content
/// so they always reflect the latest state.
class RetentionService {
  RetentionService._();
  static final RetentionService instance = RetentionService._();

  static const _boxName = 'retention_stats';

  // Fixed notification IDs that won't collide with Hive note keys.
  static const _dailyNotifId = 900000;
  static const _weeklyNotifId = 900001;
  static const _smartNotifId = 900002;

  static const _channelDaily = 'ai_sticky_daily';
  static const _channelWeekly = 'ai_sticky_weekly';

  FlutterLocalNotificationsPlugin? _plugin;

  void attachPlugin(FlutterLocalNotificationsPlugin plugin) {
    _plugin = plugin;
  }

  // ── Stats persistence ───────────────────────────────────────

  Future<Box> get _box async => Hive.openBox(_boxName);

  Future<void> recordTaskCompleted() async {
    final box = await _box;
    final key = _weekKey(DateTime.now());
    final current = box.get(key, defaultValue: 0) as int;
    await box.put(key, current + 1);
  }

  Future<void> recordNoteCreated() async {
    final box = await _box;
    final key = 'notes_${_weekKey(DateTime.now())}';
    final current = box.get(key, defaultValue: 0) as int;
    await box.put(key, current + 1);
  }

  Future<int> tasksCompletedThisWeek() async {
    final box = await _box;
    return box.get(_weekKey(DateTime.now()), defaultValue: 0) as int;
  }

  Future<int> notesCreatedThisWeek() async {
    final box = await _box;
    return box.get('notes_${_weekKey(DateTime.now())}', defaultValue: 0) as int;
  }

  static String _weekKey(DateTime dt) {
    final monday = dt.subtract(Duration(days: dt.weekday - 1));
    return 'tasks_w${monday.year}_${monday.month}_${monday.day}';
  }

  // ── Scheduling ──────────────────────────────────────────────

  /// Analyses [notes] and (re)schedules daily + weekly notifications.
  /// Call after loadNotes / addNote / updateNote / deleteNote.
  Future<void> reschedule(List<Note> notes) async {
    if (kIsWeb || _plugin == null) return;

    try {
      // Cancel previous scheduled retention notifications.
      await _plugin!.cancel(_dailyNotifId);
      await _plugin!.cancel(_weeklyNotifId);
      await _plugin!.cancel(_smartNotifId);

      await _scheduleDailyReminder(notes);
      await _scheduleSmartNudge(notes);
      await _scheduleWeeklyInsight();
    } catch (e) {
      SecurityService.log('Retention', 'Scheduling failed: $e');
    }
  }

  // ── Daily task reminder (9 AM) ──────────────────────────────

  Future<void> _scheduleDailyReminder(List<Note> notes) async {
    final pending = _countPendingTasks(notes);
    if (pending == 0) return; // Nothing to nudge about.

    final title = 'You have $pending pending task${pending > 1 ? 's' : ''}';
    const body = 'Open AI Sticky Notes to check them off!';

    final nextFire = _next9AM();
    await _schedule(
      id: _dailyNotifId,
      title: title,
      body: body,
      at: nextFire,
      channel: _channelDaily,
      channelName: 'Daily Check-in',
      channelDesc: 'Daily reminder about pending tasks',
    );
  }

  // ── Smart contextual nudge (6 PM) ──────────────────────────

  Future<void> _scheduleSmartNudge(List<Note> notes) async {
    final nudge = _buildSmartNudge(notes);
    if (nudge == null) return;

    final nextFire = _next6PM();
    await _schedule(
      id: _smartNotifId,
      title: nudge.title,
      body: nudge.body,
      at: nextFire,
      channel: _channelDaily,
      channelName: 'Daily Check-in',
      channelDesc: 'Smart contextual nudges',
    );
  }

  // ── Weekly insight (Sunday 10 AM) ───────────────────────────

  Future<void> _scheduleWeeklyInsight() async {
    final tasks = await tasksCompletedThisWeek();
    final created = await notesCreatedThisWeek();

    String title;
    String body;

    if (tasks > 0) {
      title = 'Weekly Recap: $tasks task${tasks > 1 ? 's' : ''} completed!';
      body = 'You created $created note${created != 1 ? 's' : ''} this week. Keep the momentum going!';
    } else if (created > 0) {
      title = 'Weekly Recap: $created note${created != 1 ? 's' : ''} this week';
      body = 'You\'re building great habits. Try adding tasks to your notes!';
    } else {
      title = 'Your notes miss you!';
      body = 'Start the week fresh. Tap to create a new note.';
    }

    final nextSunday = _nextSunday10AM();
    await _schedule(
      id: _weeklyNotifId,
      title: title,
      body: body,
      at: nextSunday,
      channel: _channelWeekly,
      channelName: 'Weekly Insight',
      channelDesc: 'Weekly accomplishment summary every Sunday',
    );
  }

  // ── Helpers ─────────────────────────────────────────────────

  Future<void> _schedule({
    required int id,
    required String title,
    required String body,
    required DateTime at,
    required String channel,
    required String channelName,
    required String channelDesc,
  }) async {
    if (at.isBefore(DateTime.now())) return;

    final android = AndroidNotificationDetails(
      channel,
      channelName,
      channelDescription: channelDesc,
      importance: Importance.high,
      priority: Priority.high,
      styleInformation: BigTextStyleInformation(body),
    );

    try {
      await _plugin!.zonedSchedule(
        id,
        title,
        body,
        tz.TZDateTime.from(at, tz.local),
        NotificationDetails(android: android),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.wallClockTime,
      );
    } catch (e) {
      SecurityService.log('Retention', 'Failed to schedule $id: $e');
    }
  }

  /// Counts lines matching `- [ ]` (unchecked task) across all notes.
  static int _countPendingTasks(List<Note> notes) {
    int count = 0;
    final pattern = RegExp(r'^\s*-\s*\[\s*\]', multiLine: true);
    for (final n in notes) {
      count += pattern.allMatches(n.content).length;
    }
    return count;
  }

  /// Counts lines matching `- [x]` or `- [X]` (checked task) across all notes.
  static int countCompletedTasks(List<Note> notes) {
    int count = 0;
    final pattern = RegExp(r'^\s*-\s*\[[xX]\]', multiLine: true);
    for (final n in notes) {
      count += pattern.allMatches(n.content).length;
    }
    return count;
  }

  /// Builds a context-aware nudge from today's notes.
  static ({String title, String body})? _buildSmartNudge(List<Note> notes) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));

    // Look for notes with reminders set for today that haven't fired yet.
    final todayNotes = notes.where((n) {
      if (n.reminderTime == null) return false;
      final r = n.reminderTime!;
      return r.isAfter(now) && r.isBefore(tomorrow);
    }).toList();

    if (todayNotes.isEmpty) return null;

    final first = todayNotes.first;
    final title = first.title.isNotEmpty ? first.title : 'Your note';
    final cleanTitle = title.replaceAll(RegExp(r'^[\p{Emoji}\s]+', unicode: true), '').trim();

    if (todayNotes.length == 1) {
      return (
        title: 'Still on for today?',
        body: 'You planned "$cleanTitle". Don\'t forget!',
      );
    }

    return (
      title: '${todayNotes.length} things planned today',
      body: '"$cleanTitle" and ${todayNotes.length - 1} more. You got this!',
    );
  }

  static DateTime _next9AM() {
    final now = DateTime.now();
    var next = DateTime(now.year, now.month, now.day, 9, 0);
    if (next.isBefore(now)) next = next.add(const Duration(days: 1));
    return next;
  }

  static DateTime _next6PM() {
    final now = DateTime.now();
    var next = DateTime(now.year, now.month, now.day, 18, 0);
    if (next.isBefore(now)) next = next.add(const Duration(days: 1));
    return next;
  }

  static DateTime _nextSunday10AM() {
    final now = DateTime.now();
    var sunday = now.add(Duration(days: DateTime.sunday - now.weekday));
    if (sunday.weekday != DateTime.sunday) {
      sunday = now.add(Duration(days: (7 - now.weekday) % 7));
    }
    var at = DateTime(sunday.year, sunday.month, sunday.day, 10, 0);
    // If it's already past Sunday 10 AM this week, go to next Sunday.
    if (at.isBefore(now)) at = at.add(const Duration(days: 7));
    return at;
  }
}
