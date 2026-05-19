import 'package:flutter/material.dart';

import '../models/note.dart';
import '../services/ai_service.dart';
import '../services/streak_service.dart';

/// A personalized daily briefing card shown at the top of the home screen.
/// Shows greeting, streak, pending tasks, and an AI-generated daily insight.
class DailyBriefingCard extends StatefulWidget {
  final List<Note> notes;

  const DailyBriefingCard({super.key, required this.notes});

  @override
  State<DailyBriefingCard> createState() => _DailyBriefingCardState();
}

class _DailyBriefingCardState extends State<DailyBriefingCard>
    with SingleTickerProviderStateMixin {
  int _streak = 0;
  int _pendingTasks = 0;
  int _todayReminders = 0;
  String? _aiInsight;
  bool _loadingInsight = false;

  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _loadData();
  }

  @override
  void didUpdateWidget(DailyBriefingCard old) {
    super.didUpdateWidget(old);
    if (old.notes.length != widget.notes.length) _computeStats();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  void _computeStats() {
    int tasks = 0;
    int reminders = 0;
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(const Duration(days: 1));

    for (final note in widget.notes) {
      final lines = note.content.split('\n');
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.startsWith('- [ ]') || trimmed.startsWith('- []')) {
          tasks++;
        }
      }
      if (note.reminderTime != null &&
          note.reminderTime!.isAfter(todayStart) &&
          note.reminderTime!.isBefore(todayEnd)) {
        reminders++;
      }
    }

    if (mounted) {
      setState(() {
        _pendingTasks = tasks;
        _todayReminders = reminders;
      });
    }
  }

  Future<void> _loadData() async {
    _computeStats();

    final streak = await StreakService.instance.getStreak();
    if (mounted) setState(() => _streak = streak);

    if (!AiService.instance.hasApiKey || widget.notes.isEmpty) {
      _fadeCtrl.forward();
      return;
    }

    setState(() => _loadingInsight = true);
    try {
      final insight = await AiService.instance.generateDailyBriefing(
        notes: widget.notes,
        pendingTasks: _pendingTasks,
        streak: _streak,
      );
      if (mounted) setState(() => _aiInsight = insight);
    } catch (_) {}

    if (mounted) {
      setState(() => _loadingInsight = false);
      _fadeCtrl.forward();
    }
  }

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return FadeTransition(
      opacity: _fadeAnim,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [cs.primaryContainer, cs.tertiaryContainer],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$_greeting!',
                    style: tt.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: cs.onPrimaryContainer,
                    ),
                  ),
                ),
                if (_streak > 0)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: cs.primary.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.local_fire_department,
                            size: 16, color: cs.primary),
                        const SizedBox(width: 4),
                        Text(
                          '$_streak day${_streak == 1 ? '' : 's'}',
                          style: tt.labelMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: cs.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 12),

            // Stats chips
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (_pendingTasks > 0)
                  _StatChip(
                    icon: Icons.check_circle_outline,
                    label:
                        '$_pendingTasks task${_pendingTasks == 1 ? '' : 's'}',
                    color: cs.onPrimaryContainer,
                  ),
                if (_todayReminders > 0)
                  _StatChip(
                    icon: Icons.alarm,
                    label:
                        '$_todayReminders reminder${_todayReminders == 1 ? '' : 's'} today',
                    color: cs.onPrimaryContainer,
                  ),
                if (_pendingTasks == 0 && _todayReminders == 0)
                  _StatChip(
                    icon: Icons.celebration_outlined,
                    label: 'All clear today!',
                    color: cs.onPrimaryContainer,
                  ),
              ],
            ),

            // AI insight
            if (_loadingInsight) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: cs.onPrimaryContainer.withOpacity(0.5),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Thinking...',
                    style: tt.bodySmall?.copyWith(
                      color: cs.onPrimaryContainer.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            ] else if (_aiInsight != null) ...[
              const SizedBox(height: 14),
              Text(
                _aiInsight!,
                style: tt.bodyMedium?.copyWith(
                  color: cs.onPrimaryContainer.withOpacity(0.85),
                  height: 1.5,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _StatChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color.withOpacity(0.7)),
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: color.withOpacity(0.8),
                fontWeight: FontWeight.w500,
              ),
        ),
      ],
    );
  }
}
