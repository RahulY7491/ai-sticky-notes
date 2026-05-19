import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/note.dart';
import '../services/ai_service.dart';
import '../services/reminder_service.dart';
import '../services/security_service.dart';
import '../services/smart_share_service.dart';
import '../services/usage_gate.dart';
import '../widgets/ai_action_button.dart';
import '../widgets/assistant_suggestion_bar.dart';
import 'home_screen.dart';

class NoteEditorScreen extends StatefulWidget {
  final Note? note;

  const NoteEditorScreen({super.key, this.note});

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  late TextEditingController _titleController;
  late TextEditingController _contentController;
  DateTime? _reminderTime;
  late int _colorIndex;
  bool _isSaving = false;
  bool _isAiProcessing = false;

  // ── Auto Life Assistant state ─────────────────────────────
  Timer? _analysisDebounce;
  bool _isAnalysing = false;
  AssistantInsight? _insight;
  String _lastAnalysedText = '';

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.note?.title ?? '');
    _contentController =
        TextEditingController(text: widget.note?.content ?? '');
    _reminderTime = widget.note?.reminderTime;
    _colorIndex = widget.note?.colorIndex ?? 0;
    ReminderService.instance.init();

    _titleController.addListener(_onTextChanged);
    _contentController.addListener(_onTextChanged);

    // If opening an existing note with content, run analysis once after build.
    final initial = _combinedText();
    if (initial.length >= 8 && AiService.instance.hasApiKey) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _runAnalysis(initial);
      });
    }
  }

  @override
  void dispose() {
    _analysisDebounce?.cancel();
    _titleController.removeListener(_onTextChanged);
    _contentController.removeListener(_onTextChanged);
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  // ── Auto Life Assistant logic ─────────────────────────────

  void _onTextChanged() {
    _analysisDebounce?.cancel();
    final combined = _combinedText();
    // Only fire when there's meaningful text and it actually changed.
    if (combined.length < 8 || combined == _lastAnalysedText) return;
    _analysisDebounce = Timer(const Duration(milliseconds: 1800), () {
      _runAnalysis(combined);
    });
  }

  String _combinedText() {
    final t = _titleController.text.trim();
    final c = _contentController.text.trim();
    return [t, c].where((s) => s.isNotEmpty).join('\n');
  }

  Future<void> _runAnalysis(String text) async {
    if (!AiService.instance.hasApiKey || _isAnalysing) return;
    _lastAnalysedText = text;
    setState(() => _isAnalysing = true);
    try {
      SecurityService.log('Assistant', 'Analysing note (${text.length} chars)…');
      final result = await AiService.instance.analyzeNoteContext(
        text,
        DateTime.now(),
      );
      if (!mounted) return;

      final reminder = result['reminder']?.toString();
      final rawTasks = result['tasks'];
      final tasks = <String>[];
      if (rawTasks is List) {
        for (final t in rawTasks) {
          final s = t?.toString().trim();
          if (s != null && s.isNotEmpty) tasks.add(s);
        }
      }
      final suggestion = result['suggestion']?.toString();

      SecurityService.log('Assistant', 'reminder=$reminder  tasks=$tasks  suggestion=$suggestion');

      DateTime? reminderDt;
      if (reminder != null && reminder.isNotEmpty && reminder != 'null') {
        try {
          reminderDt = DateTime.parse(reminder);
          if (reminderDt.isBefore(DateTime.now())) reminderDt = null;
        } catch (_) {}
      }

      setState(() {
        _insight = AssistantInsight(
          reminder: reminderDt,
          tasks: tasks,
          suggestion: (suggestion != null && suggestion != 'null') ? suggestion : null,
        );
        _isAnalysing = false;
      });
    } catch (e, st) {
      SecurityService.log('Assistant', 'Analysis failed: $e\n$st');
      if (mounted) setState(() => _isAnalysing = false);
    }
  }

  void _acceptReminder(DateTime dt) {
    setState(() {
      _reminderTime = dt;
      _insight = AssistantInsight(
        tasks: _insight?.tasks ?? [],
        suggestion: _insight?.suggestion,
      );
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.alarm_on_rounded, color: Colors.white, size: 16),
            const SizedBox(width: 8),
            Text('Reminder set for ${_formatReminderLabel(dt)}'),
          ],
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// MVP: one tap — set suggested reminder and append checklist tasks.
  void _applyAllActions() {
    final i = _insight;
    if (i == null) return;
    final now = DateTime.now();
    DateTime? rem = i.reminder;
    if (rem != null && !rem.isAfter(now)) rem = null;

    final tasks = i.tasks;
    final parts = <String>[];

    setState(() {
      if (rem != null) _reminderTime = rem;
      if (tasks.isNotEmpty) {
        final current = _contentController.text;
        final sep = current.endsWith('\n') || current.isEmpty ? '' : '\n\n';
        final tasksText = tasks.map((t) => '- [ ] $t').join('\n');
        _contentController.text = '$current$sep$tasksText';
        _contentController.selection = TextSelection.fromPosition(
          TextPosition(offset: _contentController.text.length),
        );
      }
      _insight = null;
    });
    _lastAnalysedText = _combinedText();

    if (rem != null) parts.add('Reminder set');
    if (tasks.isNotEmpty) {
      parts.add('${tasks.length} task${tasks.length > 1 ? 's' : ''} added');
    }
    if (parts.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.bolt_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(parts.join(' · '))),
          ],
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _insertTasks(List<String> tasks) {
    final current = _contentController.text;
    final sep = current.endsWith('\n') || current.isEmpty ? '' : '\n\n';
    final tasksText = tasks.map((t) => '- [ ] $t').join('\n');
    _contentController.text = '$current$sep$tasksText';
    _contentController.selection = TextSelection.fromPosition(
      TextPosition(offset: _contentController.text.length),
    );
    setState(() {
      _insight = AssistantInsight(
        reminder: _insight?.reminder,
        suggestion: _insight?.suggestion,
      );
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${tasks.length} task${tasks.length > 1 ? 's' : ''} added to note'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _runSuggestionAction() {
    final suggestion = _insight?.suggestion;
    if (suggestion == null) return;

    // Map the suggestion to the appropriate AI action.
    final lower = suggestion.toLowerCase();
    if (lower.contains('email')) {
      _runAi(AiService.instance.generateEmail);
    } else if (lower.contains('summar')) {
      _runAi(AiService.instance.summarizeNote);
    } else if (lower.contains('task') || lower.contains('checklist') || lower.contains('list')) {
      _runAi(AiService.instance.extractTasks);
    } else {
      _runAi(AiService.instance.summarizeNote);
    }
  }

  void _dismissInsight() => setState(() {
        _insight = null;
        _lastAnalysedText = _combinedText(); // prevent re-triggering same text
      });

  static DateTime _laterToday() {
    final now = DateTime.now();
    var at = DateTime(now.year, now.month, now.day, 18, 0); // 6 PM
    if (now.hour >= 20) {
      at = at.add(const Duration(days: 1));
    } else if (now.hour >= 18) {
      at = DateTime(now.year, now.month, now.day, 20, 0);
    } else if (now.hour >= 14) {
      at = DateTime(now.year, now.month, now.day, 18, 0);
    } else if (now.hour >= 12) {
      at = DateTime(now.year, now.month, now.day, 14, 0);
    } else {
      at = DateTime(now.year, now.month, now.day, 12, 0);
    }
    return at.isBefore(now) ? at.add(const Duration(days: 1)) : at;
  }

  static DateTime _tomorrowMorning() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day + 1, 9, 0);
  }

  static DateTime _nextWeek() {
    final now = DateTime.now();
    return now.add(const Duration(days: 7));
  }

  void _setReminderPreset(DateTime? value) {
    setState(() => _reminderTime = value);
  }

  Future<void> _showReminderOptions() async {
    final chosen = await showModalBottomSheet<DateTime?>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Remind me', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            ),
            ListTile(
              leading: const Icon(Icons.schedule),
              title: const Text('Later today'),
              subtitle: Text(TimeOfDay.fromDateTime(_laterToday()).format(ctx)),
              onTap: () => Navigator.pop(ctx, _laterToday()),
            ),
            ListTile(
              leading: const Icon(Icons.wb_sunny_outlined),
              title: const Text('Tomorrow morning'),
              subtitle: Text('${_tomorrowMorning().day}/${_tomorrowMorning().month} at 9:00'),
              onTap: () => Navigator.pop(ctx, _tomorrowMorning()),
            ),
            ListTile(
              leading: const Icon(Icons.date_range),
              title: const Text('Next week'),
              subtitle: Text('${_nextWeek().day}/${_nextWeek().month}'),
              onTap: () => Navigator.pop(ctx, _nextWeek()),
            ),
            ListTile(
              leading: const Icon(Icons.calendar_today),
              title: const Text('Pick date & time'),
              onTap: () async {
                Navigator.pop(ctx);
                await _pickReminderCustom();
              },
            ),
            if (_reminderTime != null)
              ListTile(
                leading: const Icon(Icons.notifications_off_outlined),
                title: const Text('Remove reminder'),
                onTap: () => Navigator.pop(ctx, null),
              ),
          ],
        ),
      ),
    );
    _setReminderPreset(chosen);
  }

  Future<void> _pickReminderCustom() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _reminderTime ?? now,
      firstDate: now,
      lastDate: DateTime(now.year + 2),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: _reminderTime != null
          ? TimeOfDay.fromDateTime(_reminderTime!)
          : TimeOfDay.fromDateTime(now),
    );
    if (time == null || !mounted) return;

    setState(() {
      _reminderTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _saveNote() async {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();

    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Note content cannot be empty')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final provider = context.read<NotesProvider>();
      final now = DateTime.now();
      late Note savedNote;

      if (widget.note == null) {
        savedNote = await provider.addNote(Note(
          title: title,
          content: content,
          createdAt: now,
          updatedAt: now,
          reminderTime: _reminderTime,
          colorIndex: _colorIndex,
        ));
      } else {
        savedNote = widget.note!.copyWith(
          title: title,
          content: content,
          updatedAt: now,
          reminderTime: _reminderTime,
          colorIndex: _colorIndex,
        );
        await provider.updateNote(savedNote);
      }

      // Capture refs before Navigator.pop() invalidates the context.
      final scaffoldMsg = ScaffoldMessenger.of(context);

      if (mounted) Navigator.of(context).pop();

      // If the user already set a reminder manually, skip AI detection.
      if (_reminderTime == null) {
        _detectAndSuggestReminder(
          scaffoldMsg: scaffoldMsg,
          provider: provider,
          note: savedNote,
          text: [title, content].where((s) => s.isNotEmpty).join('\n'),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// Runs Gemini reminder detection silently in the background.
  /// Shows a SnackBar suggestion if a future date/time is found.
  void _detectAndSuggestReminder({
    required ScaffoldMessengerState scaffoldMsg,
    required NotesProvider provider,
    required Note note,
    required String text,
  }) {
    AiService.instance.detectReminder(text, DateTime.now()).then((detected) {
      if (detected == null || detected.isBefore(DateTime.now())) return;
      final label = _formatReminderLabel(detected);
      scaffoldMsg.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.alarm_outlined, color: Colors.white, size: 18),
              const SizedBox(width: 10),
              Expanded(child: Text('Remind you $label?')),
            ],
          ),
          duration: const Duration(seconds: 8),
          action: SnackBarAction(
            label: 'Set',
            onPressed: () async {
              final updated = note.copyWith(reminderTime: detected);
              await provider.updateNote(updated);
            },
          ),
        ),
      );
    }).catchError((_) {/* silent — reminder detection is best-effort */});
  }

  /// Returns a human-friendly label like "tomorrow at 10:00 AM" or "Fri at 3:30 PM".
  static String _formatReminderLabel(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(dt.year, dt.month, dt.day);
    final diff = day.difference(today).inDays;

    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour < 12 ? 'AM' : 'PM';
    final timeStr = '$hour:$minute $period';

    if (diff == 0) return 'today at $timeStr';
    if (diff == 1) return 'tomorrow at $timeStr';
    if (diff <= 6) {
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return '${days[dt.weekday - 1]} at $timeStr';
    }
    return '${dt.day}/${dt.month} at $timeStr';
  }

  Future<void> _deleteCurrentNote() async {
    final note = widget.note;
    if (note == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete note?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      final provider = context.read<NotesProvider>();
      await provider.deleteNote(note);
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Note deleted')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete: $e')),
      );
    }
  }

  Future<void> _runAi(Future<String> Function(String) fn) async {
    final content = _contentController.text.trim();
    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add some content before using AI')),
      );
      return;
    }

    if (!await UsageGate.instance.guardAiAction(context)) return;

    setState(() => _isAiProcessing = true);

    try {
      final result = await fn(content);
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('AI Result'),
          content: SingleChildScrollView(child: Text(result)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close'),
            ),
            TextButton(
              onPressed: () {
                _contentController.text = result;
                Navigator.of(ctx).pop();
              },
              child: const Text('Replace note'),
            ),
          ],
        ),
      );
    } catch (e, st) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg.length > 120 ? '${msg.substring(0, 120)}...' : msg),
          duration: const Duration(seconds: 5),
        ),
      );
      SecurityService.log('AI', 'error: $e\n$st');
    } finally {
      if (mounted) setState(() => _isAiProcessing = false);
    }
  }

  void _shareNote() {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();
    if (content.isEmpty && title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nothing to share')),
      );
      return;
    }
    final now = DateTime.now();
    final note = widget.note?.copyWith(
          title: title,
          content: content,
          updatedAt: now,
        ) ??
        Note(
          title: title,
          content: content,
          createdAt: now,
          updatedAt: now,
        );
    SmartShareService.shareNote(context, note);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final noteColor = NoteColors.of(_colorIndex, brightness);
    final hasColor = _colorIndex > 0;

    return Scaffold(
      backgroundColor: hasColor ? noteColor : null,
      appBar: AppBar(
        backgroundColor: hasColor ? noteColor : null,
        title: Text(widget.note == null ? 'New Note' : 'Edit Note'),
        actions: [
          AiActionButton(
            onSummarize: () => _runAi(AiService.instance.summarizeNote),
            onExtractTasks: () => _runAi(AiService.instance.extractTasks),
            onGenerateEmail: () => _runAi(AiService.instance.generateEmail),
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined),
            onPressed: _shareNote,
          ),
          if (widget.note != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _deleteCurrentNote,
            ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Column(
                    children: [
                      TextField(
                        controller: _titleController,
                        decoration: const InputDecoration(
                          hintText: 'Title',
                          border: InputBorder.none,
                        ),
                        style: theme.textTheme.titleLarge,
                      ),
                      const Divider(),
                      Expanded(
                        child: TextField(
                          controller: _contentController,
                          decoration: const InputDecoration(
                            hintText: 'Start typing your note...',
                            border: InputBorder.none,
                          ),
                          maxLines: null,
                          keyboardType: TextInputType.multiline,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Auto Life Assistant suggestion bar ──────────
              AssistantSuggestionBar(
                insight: _insight,
                isLoading: _isAnalysing,
                onSetReminder: _acceptReminder,
                onInsertTasks: _insertTasks,
                onRunSuggestion: _runSuggestionAction,
                onApplyAll: _applyAllActions,
                onDismiss: _dismissInsight,
              ),

              // ── Color picker row ───────────────────────────
              SizedBox(
                height: 44,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: NoteColors.count,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final color = i == 0
                        ? theme.colorScheme.surfaceContainerHighest
                        : NoteColors.of(i, brightness);
                    final isSelected = i == _colorIndex;
                    return GestureDetector(
                      onTap: () => setState(() => _colorIndex = i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected
                                ? theme.colorScheme.primary
                                : theme.colorScheme.outline.withOpacity(0.3),
                            width: isSelected ? 2.5 : 1,
                          ),
                        ),
                        child: isSelected
                            ? Icon(Icons.check,
                                size: 16, color: theme.colorScheme.primary)
                            : null,
                      ),
                    );
                  },
                ),
              ),

              // ── Bottom action row ──────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton.icon(
                      onPressed: _showReminderOptions,
                      icon: const Icon(Icons.notifications_active_outlined),
                      label: Text(
                        _reminderTime == null
                            ? 'Remind me'
                            : '${TimeOfDay.fromDateTime(_reminderTime!).format(context)} · ${_reminderTime!.day}/${_reminderTime!.month}',
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: _isSaving ? null : _saveNote,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Save'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_isAiProcessing)
            Container(
              color: Colors.black.withOpacity(0.1),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}
