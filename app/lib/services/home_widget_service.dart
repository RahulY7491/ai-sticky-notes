import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

/// Manages the home-screen widget data.
///
/// Two display modes:
///  • **Pinned** – a specific note chosen by the user is shown.
///  • **Auto**   – the most-recent note count + title is shown.
class HomeWidgetService {
  static const _androidName = 'NotesWidgetProvider';

  // Auto-mode keys
  static const _keyCount = 'notes_count';
  static const _keyTitle = 'notes_title';

  // Pinned-mode keys
  static const _keyPinnedId = 'pinned_note_id';
  static const _keyPinnedTitle = 'pinned_title';
  static const _keyPinnedBody = 'pinned_body';

  // ── Auto update (called after every add / edit / delete) ──

  static Future<void> updateWidget({
    required int count,
    String? lastTitle,
  }) async {
    if (kIsWeb) return;
    try {
      await HomeWidget.saveWidgetData<int>(_keyCount, count);
      await HomeWidget.saveWidgetData<String>(
        _keyTitle,
        _truncate(lastTitle),
      );
      await HomeWidget.updateWidget(androidName: _androidName);
    } catch (_) {}
  }

  // ── Pin a specific note to the widget ──────────────────────

  static Future<void> pinNote({
    required int id,
    required String title,
    required String body,
  }) async {
    if (kIsWeb) return;
    try {
      await HomeWidget.saveWidgetData<int>(_keyPinnedId, id);
      await HomeWidget.saveWidgetData<String>(_keyPinnedTitle, _truncate(title, max: 50));
      await HomeWidget.saveWidgetData<String>(_keyPinnedBody, _truncate(body, max: 80));
      await HomeWidget.updateWidget(androidName: _androidName);
    } catch (_) {}
  }

  // ── Clear pin (return to auto mode) ───────────────────────

  static Future<void> clearPin() async {
    if (kIsWeb) return;
    try {
      await HomeWidget.saveWidgetData<int?>(_keyPinnedId, null);
      await HomeWidget.saveWidgetData<String?>(_keyPinnedTitle, null);
      await HomeWidget.saveWidgetData<String?>(_keyPinnedBody, null);
      await HomeWidget.updateWidget(androidName: _androidName);
    } catch (_) {}
  }

  // ── Read back the pinned note ID (to restore state on launch) ──

  static Future<int?> getPinnedNoteId() async {
    if (kIsWeb) return null;
    try {
      final id = await HomeWidget.getWidgetData<int>(
        _keyPinnedId,
        defaultValue: -1,
      );
      return (id == null || id < 0) ? null : id;
    } catch (_) {
      return null;
    }
  }

  // ── Helpers ───────────────────────────────────────────────

  static String? _truncate(String? s, {int max = 40}) {
    if (s == null || s.isEmpty) return null;
    return s.length > max ? '${s.substring(0, max)}…' : s;
  }
}
