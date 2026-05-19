import 'package:hive_flutter/hive_flutter.dart';

import '../models/note.dart';
import 'database_service.dart';

/// Manages first-launch state and demo content seeding.
class OnboardingService {
  static const _boxName = 'onboarding';
  static const _keySeeded = 'demo_seeded';
  static const _keyCoachShown = 'mic_coach_shown';

  static Future<bool> get isFirstLaunch async {
    final box = await Hive.openBox(_boxName);
    return box.get(_keySeeded, defaultValue: false) != true;
  }

  static Future<bool> get isMicCoachShown async {
    final box = await Hive.openBox(_boxName);
    return box.get(_keyCoachShown, defaultValue: false) == true;
  }

  static Future<void> markMicCoachShown() async {
    final box = await Hive.openBox(_boxName);
    await box.put(_keyCoachShown, true);
  }

  /// Seeds 3 demo notes so the app doesn't start empty.
  /// Returns the created notes (already persisted in Hive).
  static Future<List<Note>> seedDemoNotes() async {
    final box = await Hive.openBox(_boxName);
    if (box.get(_keySeeded, defaultValue: false) == true) return [];

    final now = DateTime.now();
    final tomorrow5pm = DateTime(now.year, now.month, now.day + 1, 17, 0);

    final demos = [
      Note(
        title: '📞 Meeting with client tomorrow 5 PM',
        content: 'Discuss project timeline and deliverables.\nBring updated proposal.',
        createdAt: now,
        updatedAt: now,
        reminderTime: tomorrow5pm,
      ),
      Note(
        title: '🛒 Buy groceries',
        content: 'Milk, eggs, bread, vegetables, chicken, rice.',
        createdAt: now.subtract(const Duration(minutes: 1)),
        updatedAt: now.subtract(const Duration(minutes: 1)),
      ),
      Note(
        title: '💪 Gym at 6 AM',
        content: 'Chest & back day.\nDon\'t forget water bottle.',
        createdAt: now.subtract(const Duration(minutes: 2)),
        updatedAt: now.subtract(const Duration(minutes: 2)),
        reminderTime: DateTime(now.year, now.month, now.day + 1, 6, 0),
      ),
    ];

    final db = DatabaseService.instance;
    final created = <Note>[];
    for (final note in demos) {
      created.add(await db.createNote(note));
    }

    await box.put(_keySeeded, true);
    return created;
  }
}
