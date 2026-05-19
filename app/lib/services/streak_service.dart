import 'package:hive_flutter/hive_flutter.dart';

/// Tracks consecutive days of note activity (Duolingo-style streaks).
class StreakService {
  StreakService._();
  static final StreakService instance = StreakService._();

  static const _boxName = 'streaks';
  static const _keyLastActive = 'last_active';
  static const _keyStreak = 'streak';
  static const _keyBest = 'best_streak';
  static const _keyTotalNotes = 'total_notes';
  static const _keyTotalAi = 'total_ai_actions';

  Future<Box> get _box async {
    if (Hive.isBoxOpen(_boxName)) return Hive.box(_boxName);
    return Hive.openBox(_boxName);
  }

  /// Call this whenever the user creates/edits a note.
  Future<void> recordActivity() async {
    final box = await _box;
    final today = _dateKey(DateTime.now());
    final lastActive = box.get(_keyLastActive) as String?;

    if (lastActive == today) return;

    final yesterday =
        _dateKey(DateTime.now().subtract(const Duration(days: 1)));
    int streak = (box.get(_keyStreak) as int?) ?? 0;
    int best = (box.get(_keyBest) as int?) ?? 0;

    streak = (lastActive == yesterday) ? streak + 1 : 1;
    if (streak > best) best = streak;

    await box.put(_keyLastActive, today);
    await box.put(_keyStreak, streak);
    await box.put(_keyBest, best);
  }

  Future<void> recordNoteCreated() async {
    final box = await _box;
    final count = (box.get(_keyTotalNotes) as int?) ?? 0;
    await box.put(_keyTotalNotes, count + 1);
  }

  Future<void> recordAiAction() async {
    final box = await _box;
    final count = (box.get(_keyTotalAi) as int?) ?? 0;
    await box.put(_keyTotalAi, count + 1);
  }

  /// Returns the current streak (0 if broken).
  Future<int> getStreak() async {
    final box = await _box;
    final lastActive = box.get(_keyLastActive) as String?;
    final today = _dateKey(DateTime.now());
    final yesterday =
        _dateKey(DateTime.now().subtract(const Duration(days: 1)));

    if (lastActive == today || lastActive == yesterday) {
      return (box.get(_keyStreak) as int?) ?? 0;
    }
    return 0;
  }

  Future<int> getBestStreak() async {
    final box = await _box;
    return (box.get(_keyBest) as int?) ?? 0;
  }

  Future<int> getTotalNotes() async {
    final box = await _box;
    return (box.get(_keyTotalNotes) as int?) ?? 0;
  }

  Future<int> getTotalAiActions() async {
    final box = await _box;
    return (box.get(_keyTotalAi) as int?) ?? 0;
  }

  String _dateKey(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
}
