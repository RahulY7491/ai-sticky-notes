import 'package:flutter/material.dart';

/// Data object holding all the actions the AI extracted from a note.
class AssistantInsight {
  final DateTime? reminder;
  final List<String> tasks;
  final String? suggestion;

  const AssistantInsight({this.reminder, this.tasks = const [], this.suggestion});

  bool get isEmpty => reminder == null && tasks.isEmpty && suggestion == null;
}

/// A Google-assistant–style inline suggestion bar.
///
/// Slides in from the bottom when [insight] is non-null and non-empty.
/// Calls back when the user taps individual action chips.
class AssistantSuggestionBar extends StatelessWidget {
  const AssistantSuggestionBar({
    super.key,
    required this.insight,
    required this.isLoading,
    this.onSetReminder,
    this.onInsertTasks,
    this.onRunSuggestion,
    this.onApplyAll,
    this.onDismiss,
  });

  final AssistantInsight? insight;
  final bool isLoading;
  final void Function(DateTime)? onSetReminder;
  final void Function(List<String>)? onInsertTasks;
  final VoidCallback? onRunSuggestion;
  /// One tap: set reminder + insert tasks (MVP auto-action engine).
  final VoidCallback? onApplyAll;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final show = isLoading || (insight != null && !insight!.isEmpty);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(animation),
          child: FadeTransition(opacity: animation, child: child),
        );
      },
      child: show
          ? _Bar(
              key: ValueKey(isLoading ? 'loading' : insight.hashCode),
              insight: insight,
              isLoading: isLoading,
              onSetReminder: onSetReminder,
              onInsertTasks: onInsertTasks,
              onRunSuggestion: onRunSuggestion,
              onApplyAll: onApplyAll,
              onDismiss: onDismiss,
            )
          : const SizedBox.shrink(key: ValueKey('empty')),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    super.key,
    required this.insight,
    required this.isLoading,
    this.onSetReminder,
    this.onInsertTasks,
    this.onRunSuggestion,
    this.onApplyAll,
    this.onDismiss,
  });

  final AssistantInsight? insight;
  final bool isLoading;
  final void Function(DateTime)? onSetReminder;
  final void Function(List<String>)? onInsertTasks;
  final VoidCallback? onRunSuggestion;
  final VoidCallback? onApplyAll;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: cs.surfaceVariant.withOpacity(0.55),
        border: Border(top: BorderSide(color: cs.outline.withOpacity(0.15))),
      ),
      child: SafeArea(
        top: false,
        child: isLoading
            ? _LoadingRow(cs: cs, theme: theme)
            : _ChipsRow(
                insight: insight!,
                cs: cs,
                theme: theme,
                onSetReminder: onSetReminder,
                onInsertTasks: onInsertTasks,
                onRunSuggestion: onRunSuggestion,
                onApplyAll: onApplyAll,
                onDismiss: onDismiss,
              ),
      ),
    );
  }
}

class _LoadingRow extends StatelessWidget {
  const _LoadingRow({required this.cs, required this.theme});
  final ColorScheme cs;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
          ),
          const SizedBox(width: 10),
          Text(
            'Understanding your note…',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChipsRow extends StatelessWidget {
  const _ChipsRow({
    required this.insight,
    required this.cs,
    required this.theme,
    this.onSetReminder,
    this.onInsertTasks,
    this.onRunSuggestion,
    this.onApplyAll,
    this.onDismiss,
  });

  final AssistantInsight insight;
  final ColorScheme cs;
  final ThemeData theme;
  final void Function(DateTime)? onSetReminder;
  final void Function(List<String>)? onInsertTasks;
  final VoidCallback? onRunSuggestion;
  final VoidCallback? onApplyAll;
  final VoidCallback? onDismiss;

  String _reminderLabel(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(dt.year, dt.month, dt.day);
    final diff = day.difference(today).inDays;
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final p = dt.hour < 12 ? 'AM' : 'PM';
    final t = '$h:$m $p';
    if (diff == 0) return 'Today $t';
    if (diff == 1) return 'Tomorrow $t';
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    if (diff <= 6) return '${days[dt.weekday - 1]} $t';
    return '${dt.day}/${dt.month} $t';
  }

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];
    final hasFutureReminder = insight.reminder != null &&
        insight.reminder!.isAfter(DateTime.now());
    final hasTasks = insight.tasks.isNotEmpty;
    final showApplyAll =
        hasFutureReminder && hasTasks && onApplyAll != null;

    // One-tap apply reminder + tasks (MVP)
    if (showApplyAll) {
      chips.add(_SuggestionChip(
        icon: Icons.bolt_rounded,
        label: 'Apply all',
        color: cs.primary,
        filled: true,
        onPrimary: cs.onPrimary,
        onTap: onApplyAll,
      ));
    }

    // Reminder chip (hidden when Apply all covers both)
    if (hasFutureReminder && !showApplyAll) {
      chips.add(_SuggestionChip(
        icon: Icons.alarm_rounded,
        label: _reminderLabel(insight.reminder!),
        color: cs.primary,
        onTap: () => onSetReminder?.call(insight.reminder!),
      ));
    }

    // Tasks chip
    if (hasTasks && !showApplyAll) {
      final count = insight.tasks.length;
      chips.add(_SuggestionChip(
        icon: Icons.checklist_rounded,
        label: '$count task${count > 1 ? 's' : ''} found',
        color: cs.tertiary,
        onTap: () => onInsertTasks?.call(insight.tasks),
      ));
    }

    // AI suggestion chip
    if (insight.suggestion != null && insight.suggestion!.isNotEmpty) {
      chips.add(_SuggestionChip(
        icon: Icons.auto_awesome,
        label: insight.suggestion!,
        color: cs.secondary,
        onTap: onRunSuggestion,
      ));
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.assistant_rounded, size: 18, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (int i = 0; i < chips.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    chips[i],
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onDismiss,
            child: Icon(Icons.close, size: 16, color: cs.onSurfaceVariant.withOpacity(0.6)),
          ),
        ],
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({
    required this.icon,
    required this.label,
    required this.color,
    this.filled = false,
    this.onPrimary,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool filled;
  final Color? onPrimary;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? color : color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 15,
                color: filled ? (onPrimary ?? color) : color,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: filled ? (onPrimary ?? color) : color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
