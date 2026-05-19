import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/note.dart';
import '../services/ai_service.dart';
import 'home_screen.dart';

// ─────────────────────────────────────────────────────────────
// Date-bucket helpers
// ─────────────────────────────────────────────────────────────

enum _Bucket { today, yesterday, thisWeek, thisMonth, older }

_Bucket _bucket(DateTime note, DateTime now) {
  final nDay = DateTime(note.year, note.month, note.day);
  final today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(nDay).inDays;
  if (diff == 0) return _Bucket.today;
  if (diff == 1) return _Bucket.yesterday;
  if (diff <= 6) return _Bucket.thisWeek;
  if (note.year == now.year && note.month == now.month) return _Bucket.thisMonth;
  return _Bucket.older;
}

String _bucketLabel(_Bucket b) => switch (b) {
      _Bucket.today => 'Today',
      _Bucket.yesterday => 'Yesterday',
      _Bucket.thisWeek => 'This Week',
      _Bucket.thisMonth => 'This Month',
      _Bucket.older => 'Earlier',
    };

String _timeLabel(DateTime dt) {
  final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
  final m = dt.minute.toString().padLeft(2, '0');
  final p = dt.hour < 12 ? 'AM' : 'PM';
  return '$h:$m $p';
}

String _dayLabel(DateTime dt) {
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${days[dt.weekday - 1]}, ${dt.day} ${months[dt.month - 1]}';
}

// ─────────────────────────────────────────────────────────────
// Pastel card colors (deterministic per note)
// ─────────────────────────────────────────────────────────────

const _kCardPalette = [
  Color(0xFFFFF9C4), // yellow
  Color(0xFFE8F5E9), // green
  Color(0xFFE3F2FD), // blue
  Color(0xFFFCE4EC), // pink
  Color(0xFFF3E5F5), // purple
  Color(0xFFE0F7FA), // cyan
  Color(0xFFFFF3E0), // orange
  Color(0xFFE8EAF6), // indigo
];

Color _cardColor(Note note) =>
    _kCardPalette[(note.id ?? note.createdAt.millisecondsSinceEpoch) %
        _kCardPalette.length];

// ─────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────

class MemoryTimelineScreen extends StatefulWidget {
  const MemoryTimelineScreen({super.key});

  @override
  State<MemoryTimelineScreen> createState() => _MemoryTimelineScreenState();
}

class _MemoryTimelineScreenState extends State<MemoryTimelineScreen> {
  // Bucket → AI reflection text (null = not yet generated)
  final Map<_Bucket, String?> _reflections = {};
  // Bucket → is loading
  final Map<_Bucket, bool> _loading = {};

  Future<void> _reflect(_Bucket bucket, List<Note> notes) async {
    if (_loading[bucket] == true) return;
    setState(() => _loading[bucket] = true);

    final texts = notes
        .map((n) => [n.title, n.content].where((s) => s.isNotEmpty).join(': '))
        .toList();

    try {
      final summary = await AiService.instance.generateMemorySummary(
        label: _bucketLabel(bucket),
        noteTexts: texts,
      );
      if (!mounted) return;
      setState(() {
        _reflections[bucket] = summary;
        _loading[bucket] = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading[bucket] = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not generate reflection. Try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final notes = context.watch<NotesProvider>().notes;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final now = DateTime.now();

    if (notes.isEmpty) {
      return Scaffold(
        appBar: _appBar(cs),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_stories_outlined, size: 64,
                  color: cs.onSurfaceVariant.withOpacity(0.4)),
              const SizedBox(height: 16),
              Text('No memories yet.',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(color: cs.onSurfaceVariant)),
              const SizedBox(height: 8),
              Text('Add notes to see your timeline here.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant)),
            ],
          ),
        ),
      );
    }

    // Group notes by bucket preserving creation order.
    final grouped = <_Bucket, List<Note>>{};
    for (final note in notes) {
      final b = _bucket(note.createdAt, now);
      grouped.putIfAbsent(b, () => []).add(note);
    }

    // Ordered bucket list (only those that have notes).
    final buckets = _Bucket.values.where(grouped.containsKey).toList();

    return Scaffold(
      appBar: _appBar(cs),
      body: ListView.builder(
        padding: const EdgeInsets.only(bottom: 32),
        itemCount: buckets.length,
        itemBuilder: (context, bi) {
          final bucket = buckets[bi];
          final bucketNotes = grouped[bucket]!;
          return _BucketSection(
            bucket: bucket,
            notes: bucketNotes,
            now: now,
            reflection: _reflections[bucket],
            isLoadingReflection: _loading[bucket] ?? false,
            onReflect: () => _reflect(bucket, bucketNotes),
            onNoteTap: (note) => Navigator.of(context)
                .pushNamed('/edit', arguments: note),
          );
        },
      ),
    );
  }

  AppBar _appBar(ColorScheme cs) => AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_stories, color: cs.primary, size: 22),
            const SizedBox(width: 8),
            const Text('Memory Timeline'),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────
// Bucket section (header + timeline cards)
// ─────────────────────────────────────────────────────────────

class _BucketSection extends StatelessWidget {
  const _BucketSection({
    required this.bucket,
    required this.notes,
    required this.now,
    required this.reflection,
    required this.isLoadingReflection,
    required this.onReflect,
    required this.onNoteTap,
  });

  final _Bucket bucket;
  final List<Note> notes;
  final DateTime now;
  final String? reflection;
  final bool isLoadingReflection;
  final VoidCallback onReflect;
  final void Function(Note) onNoteTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(top: 24, left: 20, right: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Section header ──────────────────────────────────
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _bucketLabel(bucket),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: cs.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${notes.length} ${notes.length == 1 ? 'note' : 'notes'}',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
              const Spacer(),
              // ✨ Reflect button
              _ReflectButton(
                isLoading: isLoadingReflection,
                hasReflection: reflection != null,
                onTap: onReflect,
              ),
            ],
          ),

          // ── AI reflection card ──────────────────────────────
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            child: reflection != null
                ? _ReflectionCard(text: reflection!, cs: cs, theme: theme)
                : const SizedBox.shrink(),
          ),

          const SizedBox(height: 12),

          // ── Timeline entries ────────────────────────────────
          for (int i = 0; i < notes.length; i++)
            _TimelineEntry(
              note: notes[i],
              isLast: i == notes.length - 1,
              now: now,
              onTap: () => onNoteTap(notes[i]),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// ✨ Reflect button
// ─────────────────────────────────────────────────────────────

class _ReflectButton extends StatelessWidget {
  const _ReflectButton({
    required this.isLoading,
    required this.hasReflection,
    required this.onTap,
  });

  final bool isLoading;
  final bool hasReflection;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (isLoading) {
      return Padding(
        padding: const EdgeInsets.only(right: 4),
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
        ),
      );
    }
    return TextButton.icon(
      onPressed: onTap,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: cs.primary,
      ),
      icon: Icon(
        hasReflection ? Icons.refresh : Icons.auto_awesome,
        size: 16,
      ),
      label: Text(
        hasReflection ? 'Re-reflect' : 'Reflect',
        style: const TextStyle(fontSize: 13),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// AI Reflection card
// ─────────────────────────────────────────────────────────────

class _ReflectionCard extends StatelessWidget {
  const _ReflectionCard({
    required this.text,
    required this.cs,
    required this.theme,
  });

  final String text;
  final ColorScheme cs;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12, right: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            cs.primaryContainer.withOpacity(0.55),
            cs.secondaryContainer.withOpacity(0.35),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.primary.withOpacity(0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.auto_awesome, size: 18, color: cs.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurface,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Single timeline entry (dot + connector line + note card)
// ─────────────────────────────────────────────────────────────

class _TimelineEntry extends StatelessWidget {
  const _TimelineEntry({
    required this.note,
    required this.isLast,
    required this.now,
    required this.onTap,
  });

  final Note note;
  final bool isLast;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final cardBg = _cardColor(note);
    final isDark = theme.brightness == Brightness.dark;

    // In dark mode tone the pastels down.
    final effectiveBg = isDark
        ? Color.lerp(cs.surface, cardBg, 0.25)!
        : cardBg;

    final timeStr = _timeLabel(note.createdAt);
    final dateStr = _dayLabel(note.createdAt);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Left: dot + vertical line ────────────────────
          SizedBox(
            width: 28,
            child: Column(
              children: [
                // Dot
                Container(
                  width: 12,
                  height: 12,
                  margin: const EdgeInsets.only(top: 18),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: cs.primary,
                    boxShadow: [
                      BoxShadow(
                        color: cs.primary.withOpacity(0.35),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
                // Connector line
                if (!isLast)
                  Expanded(
                    child: Center(
                      child: Container(
                        width: 2,
                        color: cs.outlineVariant.withOpacity(0.5),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(width: 10),

          // ── Right: note card ─────────────────────────────
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12, right: 4),
              child: GestureDetector(
                onTap: onTap,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    color: effectiveBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: cs.outline.withOpacity(0.18),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Time + date
                        Row(
                          children: [
                            Icon(Icons.access_time_rounded,
                                size: 13,
                                color: cs.onSurfaceVariant.withOpacity(0.7)),
                            const SizedBox(width: 4),
                            Text(
                              timeStr,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: cs.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              dateStr,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: cs.onSurfaceVariant.withOpacity(0.6),
                              ),
                            ),
                            const Spacer(),
                            if (note.reminderTime != null)
                              Icon(Icons.alarm_rounded,
                                  size: 15, color: cs.primary),
                          ],
                        ),

                        const SizedBox(height: 8),

                        // Title
                        if (note.title.isNotEmpty)
                          Text(
                            note.title,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: cs.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),

                        if (note.title.isNotEmpty && note.content.isNotEmpty)
                          const SizedBox(height: 4),

                        // Content preview
                        if (note.content.isNotEmpty)
                          Text(
                            note.content,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurface.withOpacity(0.75),
                              height: 1.4,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
