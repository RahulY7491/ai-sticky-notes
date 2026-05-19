import 'package:flutter/foundation.dart';

/// Structured output from the Brain Dump → Organize AI pipeline (MVP).
@immutable
class BrainDumpResult {
  const BrainDumpResult({
    required this.title,
    required this.bullets,
    required this.tasks,
    this.reminder,
  });

  final String title;
  final List<String> bullets;
  final List<String> tasks;
  final DateTime? reminder;

  /// Note body: bullets + optional checklist tasks.
  String get composedBody {
    final buf = StringBuffer();
    for (final b in bullets) {
      final t = b.trim();
      if (t.isEmpty) continue;
      buf.writeln('• $t');
    }
    if (tasks.isNotEmpty) {
      if (buf.isNotEmpty) buf.writeln();
      for (final t in tasks) {
        final s = t.trim();
        if (s.isEmpty) continue;
        buf.writeln('- [ ] $s');
      }
    }
    return buf.toString().trim();
  }

  bool get isEmpty =>
      title.trim().isEmpty && bullets.isEmpty && tasks.isEmpty && reminder == null;
}
