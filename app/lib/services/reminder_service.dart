import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class ReminderService {
  ReminderService._internal();

  static final ReminderService instance = ReminderService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// Exposes the shared plugin so [RetentionService] can reuse the same instance.
  FlutterLocalNotificationsPlugin get plugin => _plugin;

  bool _initialized = false;

  bool _permissionRequested = false;

  Future<void> init() async {
    if (kIsWeb) return;
    if (_initialized) return;

    try {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      await _plugin.initialize(const InitializationSettings(android: android));
    } catch (_) {
      return;
    }

    try {
      tz.initializeTimeZones();
      final String name = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(name));
    } catch (_) {
      try {
        tz.setLocalLocation(tz.UTC);
      } catch (_) {}
    }

    _initialized = true;
  }

  Future<void> _ensurePermission() async {
    if (_permissionRequested) return;
    _permissionRequested = true;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestNotificationsPermission();
    } catch (_) {}
  }

  Future<void> scheduleReminder({
    required int id,
    required DateTime dateTime,
    String? noteTitle,
  }) async {
    if (kIsWeb) return;
    if (!_initialized) await init();
    await _ensurePermission();
    if (dateTime.isBefore(DateTime.now())) return;

    try {
      final tzDateTime = tz.TZDateTime.from(dateTime, tz.local);
      const android = AndroidNotificationDetails(
        'ai_sticky_notes_reminders',
        'Reminders',
        channelDescription: 'Smart reminders for your notes',
        importance: Importance.high,
        priority: Priority.high,
      );
      await _plugin.zonedSchedule(
        id,
        noteTitle != null && noteTitle.isNotEmpty
            ? 'Reminder: $noteTitle'
            : 'Reminder: Check your note',
        null,
        tzDateTime,
        const NotificationDetails(android: android),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.wallClockTime,
        matchDateTimeComponents: DateTimeComponents.dateAndTime,
      );
    } catch (_) {}
  }

  Future<void> cancelReminder(int id) async {
    if (kIsWeb) return;
    if (!_initialized) return;
    try {
      await _plugin.cancel(id);
    } catch (_) {}
  }
}
