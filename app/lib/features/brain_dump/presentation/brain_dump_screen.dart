import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/repositories/brain_dump_repository_impl.dart';
import '../../../domain/entities/brain_dump_result.dart';
import '../../../models/note.dart';
import '../../../screens/home_screen.dart';
import '../../../services/ai_service.dart';
import '../../../services/usage_gate.dart';
import '../application/organize_brain_dump_use_case.dart';

/// MVP: one-tap flow from messy text → AI-structured note → save.
class BrainDumpScreen extends StatefulWidget {
  const BrainDumpScreen({super.key});

  @override
  State<BrainDumpScreen> createState() => _BrainDumpScreenState();
}

class _BrainDumpScreenState extends State<BrainDumpScreen> {
  late final OrganizeBrainDumpUseCase _useCase;
  final _controller = TextEditingController();
  BrainDumpResult? _preview;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _useCase = OrganizeBrainDumpUseCase(const BrainDumpRepositoryImpl());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _organize() async {
    final text = _controller.text;
    if (text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Type or paste something first')),
      );
      return;
    }

    if (!AiService.instance.hasApiKey) {
      setState(() {
        _error =
            'AI is not configured. Build with --dart-define=GEMINI_API_KEY=…';
      });
      return;
    }

    if (!await UsageGate.instance.guardAiAction(context)) return;

    setState(() {
      _busy = true;
      _error = null;
      _preview = null;
    });

    try {
      final result = await _useCase(text);
      if (!mounted) return;
      setState(() {
        _preview = result;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _save() async {
    final preview = _preview;
    if (preview == null) return;

    final provider = context.read<NotesProvider>();
    final now = DateTime.now();
    final note = Note(
      title: preview.title.trim().isEmpty ? 'Brain dump' : preview.title.trim(),
      content: preview.composedBody.isEmpty ? _controller.text.trim() : preview.composedBody,
      createdAt: now,
      updatedAt: now,
      reminderTime: preview.reminder,
    );

    final created = await provider.addNote(note);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Saved to your notes'),
        action: SnackBarAction(
          label: 'Open',
          onPressed: () {
            Navigator.of(context).pop();
            Navigator.of(context).pushNamed('/edit', arguments: created);
          },
        ),
      ),
    );
    Navigator.of(context).pop();
  }

  void _reset() {
    setState(() {
      _preview = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Brain dump'),
        actions: [
          if (_preview != null)
            TextButton(
              onPressed: _reset,
              child: const Text('Edit input'),
            ),
        ],
      ),
      body: SafeArea(
        child: _busy
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 24),
                    Text(
                      'Organizing your thoughts…',
                      style: tt.titleMedium?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Title · bullets · tasks · reminder',
                      style: tt.bodySmall?.copyWith(color: cs.outline),
                    ),
                  ],
                ),
              )
            : _preview != null
                ? _PreviewPane(
                    result: _preview!,
                    onSave: _save,
                    onBack: _reset,
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                        child: Text(
                          'Dump everything here — AI turns it into a clear note.',
                          style: tt.bodyMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: TextField(
                            controller: _controller,
                            maxLines: null,
                            expands: true,
                            textAlignVertical: TextAlignVertical.top,
                            decoration: InputDecoration(
                              hintText:
                                  'Meeting Friday, email client, buy milk, idea for app…',
                              filled: true,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            _error!,
                            style: tt.bodySmall?.copyWith(color: cs.error),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: FilledButton.icon(
                          onPressed: _organize,
                          icon: const Icon(Icons.auto_fix_high),
                          label: const Text('Organize with AI'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(double.infinity, 52),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}

class _PreviewPane extends StatelessWidget {
  const _PreviewPane({
    required this.result,
    required this.onSave,
    required this.onBack,
  });

  final BrainDumpResult result;
  final VoidCallback onSave;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Preview', style: tt.labelLarge?.copyWith(color: cs.primary)),
          const SizedBox(height: 12),
          Card(
            elevation: 0,
            color: cs.surfaceContainerHighest.withOpacity(0.5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: cs.outlineVariant.withOpacity(0.4)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.title,
                    style: tt.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  if (result.bullets.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    ...result.bullets.map(
                      (b) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('• ', style: tt.bodyLarge),
                            Expanded(child: Text(b, style: tt.bodyMedium)),
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (result.tasks.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('Tasks', style: tt.labelMedium),
                    const SizedBox(height: 6),
                    ...result.tasks.map(
                      (t) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            Icon(Icons.check_box_outline_blank,
                                size: 18, color: cs.tertiary),
                            const SizedBox(width: 8),
                            Expanded(child: Text(t, style: tt.bodyMedium)),
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (result.reminder != null) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(Icons.alarm, size: 18, color: cs.primary),
                        const SizedBox(width: 8),
                        Text(
                          _formatReminder(context, result.reminder!),
                          style: tt.bodyMedium?.copyWith(
                            color: cs.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onSave,
            icon: const Icon(Icons.save_rounded),
            label: const Text('Save note'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: onBack,
            child: const Text('Back to edit'),
          ),
        ],
      ),
    );
  }

  static String _formatReminder(BuildContext context, DateTime dt) {
    final tod = TimeOfDay.fromDateTime(dt);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(dt.year, dt.month, dt.day);
    final diff = day.difference(today).inDays;
    final timeStr = tod.format(context);
    if (diff == 0) return 'Today · $timeStr';
    if (diff == 1) return 'Tomorrow · $timeStr';
    return '${dt.day}/${dt.month}/${dt.year} · $timeStr';
  }
}
