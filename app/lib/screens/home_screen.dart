import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/note.dart';
import '../services/database_service.dart';
import '../services/home_widget_service.dart';
import '../services/onboarding_service.dart';
import '../services/reminder_service.dart';
import '../services/retention_service.dart';
import '../services/streak_service.dart';
import '../services/theme_notifier.dart';
import '../widgets/daily_briefing_card.dart';
import '../widgets/note_card.dart';
import '../widgets/voice_note_sheet.dart';

// ─────────────────────────────────────────────────────────────
// NotesProvider
// ─────────────────────────────────────────────────────────────

class NotesProvider extends ChangeNotifier {
  final DatabaseService _db = DatabaseService.instance;
  final ReminderService _reminderService = ReminderService.instance;
  final RetentionService _retention = RetentionService.instance;

  List<Note> _notes = [];
  bool _isLoading = false;
  bool _didSeedDemoNotes = false;

  int? _pinnedNoteId;

  List<Note> get notes => _notes;
  bool get isLoading => _isLoading;
  int? get pinnedNoteId => _pinnedNoteId;
  bool get didSeedDemoNotes => _didSeedDemoNotes;

  bool isPinned(Note note) => note.id != null && note.id == _pinnedNoteId;

  // ── Load ──────────────────────────────────────────────────

  Future<void> loadNotes() async {
    _isLoading = true;
    notifyListeners();

    try {
      final isFirst = await OnboardingService.isFirstLaunch;
      if (isFirst) {
        final seeded = await OnboardingService.seedDemoNotes();
        if (seeded.isNotEmpty) {
          _didSeedDemoNotes = true;
          for (final note in seeded) {
            if (note.reminderTime != null && note.id != null) {
              await _reminderService.scheduleReminder(
                id: note.id!,
                dateTime: note.reminderTime!,
                noteTitle: note.title,
              );
            }
          }
        }
      }
    } catch (_) {}

    try {
      _notes = await _db.getAllNotes();
    } catch (_) {
      _notes = [];
    }
    _pinnedNoteId = await HomeWidgetService.getPinnedNoteId();
    if (_pinnedNoteId != null && !_notes.any((n) => n.id == _pinnedNoteId)) {
      _pinnedNoteId = null;
      await HomeWidgetService.clearPin();
    }
    _retention.attachPlugin(_reminderService.plugin);

    _isLoading = false;
    notifyListeners();
    _pushWidgetData();
    _retention.reschedule(_notes);
  }

  // ── CRUD ──────────────────────────────────────────────────

  Future<Note> addNote(Note note) async {
    final created = await _db.createNote(note);
    _notes.insert(0, created);
    if (created.reminderTime != null && created.id != null) {
      await _reminderService.scheduleReminder(
        id: created.id!,
        dateTime: created.reminderTime!,
        noteTitle: created.title,
      );
    }
    notifyListeners();
    _pushWidgetData();
    _retention.recordNoteCreated();
    _retention.reschedule(_notes);
    StreakService.instance.recordActivity();
    StreakService.instance.recordNoteCreated();
    return created;
  }

  Future<void> updateNote(Note note) async {
    final oldNote = _notes.where((n) => n.id == note.id).firstOrNull;
    final oldDone =
        oldNote != null ? RetentionService.countCompletedTasks([oldNote]) : 0;

    await _db.updateNote(note);
    final index = _notes.indexWhere((n) => n.id == note.id);
    if (index != -1) _notes[index] = note;
    if (note.id != null) {
      await _reminderService.cancelReminder(note.id!);
      if (note.reminderTime != null) {
        await _reminderService.scheduleReminder(
          id: note.id!,
          dateTime: note.reminderTime!,
          noteTitle: note.title,
        );
      }
    }
    notifyListeners();

    final newDone = RetentionService.countCompletedTasks([note]);
    final diff = newDone - oldDone;
    for (var i = 0; i < diff; i++) {
      _retention.recordTaskCompleted();
    }

    if (note.id != null && note.id == _pinnedNoteId) {
      await HomeWidgetService.pinNote(
        id: note.id!,
        title: note.title,
        body: note.content,
      );
    } else {
      _pushWidgetData();
    }
    _retention.reschedule(_notes);
    StreakService.instance.recordActivity();
  }

  Future<void> deleteNote(Note note) async {
    if (note.id != null) {
      await _db.deleteNote(note.id!);
      await _reminderService.cancelReminder(note.id!);
      if (note.id == _pinnedNoteId) {
        _pinnedNoteId = null;
        await HomeWidgetService.clearPin();
      }
    }
    _notes.removeWhere((n) => n.id == note.id);
    notifyListeners();
    _pushWidgetData();
    _retention.reschedule(_notes);
  }

  // ── Widget pin ────────────────────────────────────────────

  Future<void> pinNoteToWidget(Note note) async {
    if (note.id == null) return;
    _pinnedNoteId = note.id;
    notifyListeners();
    await HomeWidgetService.pinNote(
      id: note.id!,
      title: note.title,
      body: note.content,
    );
  }

  Future<void> unpinFromWidget() async {
    _pinnedNoteId = null;
    notifyListeners();
    await HomeWidgetService.clearPin();
    _pushWidgetData();
  }

  // ── Helpers ───────────────────────────────────────────────

  Future<void> _pushWidgetData() async {
    await HomeWidgetService.updateWidget(
      count: _notes.length,
      lastTitle: _notes.isNotEmpty ? _notes.first.title : null,
    );
  }

  Note? getById(int id) {
    try {
      return _notes.firstWhere((n) => n.id == id);
    } catch (_) {
      return null;
    }
  }
}

// ─────────────────────────────────────────────────────────────
// HomeScreen
// ─────────────────────────────────────────────────────────────

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _coachShown = false;
  bool _didCheckCoach = false;

  // Search state
  bool _isSearching = false;
  String _searchQuery = '';
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      final provider = context.read<NotesProvider>();
      await provider.loadNotes();
      if (!mounted) return;

      if (provider.didSeedDemoNotes) {
        _maybeShowMicCoach();
      } else if (!_didCheckCoach) {
        _didCheckCoach = true;
        final shown = await OnboardingService.isMicCoachShown;
        if (!shown && mounted) _showMicCoach();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _maybeShowMicCoach() async {
    if (_coachShown) return;
    final shown = await OnboardingService.isMicCoachShown;
    if (shown || !mounted) return;
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    _showMicCoach();
  }

  void _showMicCoach() {
    if (_coachShown) return;
    _coachShown = true;
    OnboardingService.markMicCoachShown();
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => const _MicCoachDialog(),
    ).then((_) {
      if (mounted) setState(() {});
    });
  }

  void _startSearch() {
    setState(() => _isSearching = true);
    _searchFocus.requestFocus();
  }

  void _stopSearch() {
    setState(() {
      _isSearching = false;
      _searchQuery = '';
      _searchController.clear();
    });
  }

  List<Note> _filterNotes(List<Note> notes) {
    if (_searchQuery.isEmpty) return notes;
    final q = _searchQuery.toLowerCase();
    return notes.where((n) {
      return n.title.toLowerCase().contains(q) ||
          n.content.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final themeNotifier = context.watch<ThemeNotifier>();

    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                focusNode: _searchFocus,
                decoration: const InputDecoration(
                  hintText: 'Search notes...',
                  border: InputBorder.none,
                ),
                onChanged: (v) => setState(() => _searchQuery = v),
              )
            : const Text('AI Sticky Notes'),
        leading: _isSearching
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _stopSearch,
              )
            : null,
        actions: _isSearching
            ? [
                if (_searchQuery.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                  ),
              ]
            : [
                IconButton(
                  icon: const Icon(Icons.search),
                  tooltip: 'Search',
                  onPressed: _startSearch,
                ),
                IconButton(
                  icon: Icon(themeNotifier.icon),
                  tooltip: themeNotifier.label,
                  onPressed: themeNotifier.cycle,
                ),
                IconButton(
                  icon: const Icon(Icons.forum_outlined),
                  tooltip: 'Ask Your Notes',
                  onPressed: () =>
                      Navigator.of(context).pushNamed('/ask'),
                ),
                IconButton(
                  icon: const Icon(Icons.auto_stories_outlined),
                  tooltip: 'Memory Timeline',
                  onPressed: () =>
                      Navigator.of(context).pushNamed('/timeline'),
                ),
              ],
      ),
      body: Consumer<NotesProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.notes.isEmpty) {
            return _EmptyState(
              onAddNote: () => Navigator.of(context).pushNamed('/edit'),
              onVoiceNote: _createVoiceNote,
              onBrainDump: () =>
                  Navigator.of(context).pushNamed('/brain-dump'),
            );
          }

          final filtered = _filterNotes(provider.notes);

          return CustomScrollView(
            slivers: [
              // Daily Briefing — only when not searching
              if (!_isSearching)
                SliverToBoxAdapter(
                  child: DailyBriefingCard(notes: provider.notes),
                ),

              // Search results count
              if (_isSearching && _searchQuery.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Text(
                      '${filtered.length} result${filtered.length == 1 ? '' : 's'}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).hintColor,
                          ),
                    ),
                  ),
                ),

              // Notes list with swipe-to-delete
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final note = filtered[index];
                    final pinned = provider.isPinned(note);

                    return Dismissible(
                      key: ValueKey(note.id ?? index),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 24),
                        margin: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.error,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.delete_outline,
                            color: Colors.white),
                      ),
                      confirmDismiss: (_) async {
                        return await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Delete note?'),
                                content:
                                    const Text('This cannot be undone.'),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(ctx).pop(false),
                                    child: const Text('Cancel'),
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(ctx).pop(true),
                                    style: TextButton.styleFrom(
                                        foregroundColor: Colors.red),
                                    child: const Text('Delete'),
                                  ),
                                ],
                              ),
                            ) ??
                            false;
                      },
                      onDismissed: (_) async {
                        await provider.deleteNote(note);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Note deleted')),
                          );
                        }
                      },
                      child: NoteCard(
                        note: note,
                        isPinned: pinned,
                        searchQuery:
                            _isSearching ? _searchQuery : null,
                        onTap: () async {
                          await Navigator.of(context)
                              .pushNamed('/edit', arguments: note);
                        },
                        onPin: () async {
                          await provider.pinNoteToWidget(note);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Row(
                                  children: [
                                    const Icon(Icons.widgets_rounded,
                                        color: Colors.white, size: 16),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        '"${note.title.isEmpty ? 'Note' : note.title}" pinned to widget.',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                duration: const Duration(seconds: 3),
                              ),
                            );
                          }
                        },
                        onUnpin: () async {
                          await provider.unpinFromWidget();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text(
                                      'Widget is back to showing latest notes.')),
                            );
                          }
                        },
                        onDelete: () async {
                          await provider.deleteNote(note);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Note deleted')),
                            );
                          }
                        },
                      ),
                    );
                  },
                  childCount: filtered.length,
                ),
              ),

              // Bottom padding for FABs
              const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
            ],
          );
        },
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.small(
            heroTag: 'brain-dump-fab',
            tooltip: 'Brain dump',
            onPressed: () => Navigator.of(context).pushNamed('/brain-dump'),
            child: const Icon(Icons.psychology_outlined),
          ),
          const SizedBox(height: 10),
          FloatingActionButton(
            heroTag: 'voice-note-fab',
            onPressed: _createVoiceNote,
            tooltip: 'Voice note',
            child: const Icon(Icons.mic),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'add-note-fab',
            onPressed: () async {
              await Navigator.of(context).pushNamed('/edit');
            },
            tooltip: 'New note',
            child: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }

  Future<void> _createVoiceNote() async {
    final result = await VoiceNoteSheet.show(context);
    if (result == null || !mounted) return;

    final provider = context.read<NotesProvider>();
    final messenger = ScaffoldMessenger.of(context);

    if (result.action == 'edit') {
      await Navigator.of(context).pushNamed('/edit', arguments: result.note);
      return;
    }

    await provider.addNote(result.note);
    if (mounted) {
      messenger
          .showSnackBar(const SnackBar(content: Text('Voice note saved')));
    }
  }
}

// ─────────────────────────────────────────────────────────────
// Empty State — engaging, action-oriented
// ─────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final VoidCallback onAddNote;
  final VoidCallback onVoiceNote;
  final VoidCallback onBrainDump;

  const _EmptyState({
    required this.onAddNote,
    required this.onVoiceNote,
    required this.onBrainDump,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.auto_awesome, size: 48, color: cs.primary),
            ),
            const SizedBox(height: 28),
            Text(
              'Your AI-powered notebook',
              style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Capture thoughts, tasks, and ideas.\nAI helps you organize and act on them.',
              style: tt.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: onAddNote,
                  icon: const Icon(Icons.add),
                  label: const Text('New note'),
                ),
                FilledButton.tonalIcon(
                  onPressed: onBrainDump,
                  icon: const Icon(Icons.auto_fix_high),
                  label: const Text('Brain dump'),
                ),
                OutlinedButton.icon(
                  onPressed: onVoiceNote,
                  icon: const Icon(Icons.mic),
                  label: const Text('Voice'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// First-launch coaching dialog
// ─────────────────────────────────────────────────────────────

class _MicCoachDialog extends StatefulWidget {
  const _MicCoachDialog();

  @override
  State<_MicCoachDialog> createState() => _MicCoachDialogState();
}

class _MicCoachDialogState extends State<_MicCoachDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ScaleTransition(
              scale: Tween(begin: 0.85, end: 1.15).animate(
                CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
              ),
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.mic, size: 44, color: cs.primary),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Try your voice!',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              'Tap the mic button and say something like\n"Meeting with Rahul tomorrow at 3 PM"',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.5,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'AI will create a structured note & reminder for you.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.primary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_forward_rounded),
              label: const Text('Got it!'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
