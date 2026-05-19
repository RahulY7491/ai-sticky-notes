import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../models/note.dart';
import 'ai_service.dart';

/// Formats notes into beautiful shareable text with app branding and viral link.
class SmartShareService {
  static const _installLink =
      'https://play.google.com/store/apps/details?id=com.aistickynotes.app';

  static const _tagline = 'Created with AI Sticky Notes';

  /// Formats a note using AI into a polished, branded share card.
  /// Falls back to a clean manual format if AI is unavailable or fails.
  static Future<String> formatNote(Note note) async {
    final title = note.title.trim();
    final content = note.content.trim();

    if (content.isEmpty && title.isEmpty) return '';

    try {
      if (AiService.instance.hasApiKey) {
        final raw = [title, content].where((s) => s.isNotEmpty).join('\n');
        final formatted = await AiService.instance.formatForShare(raw);
        if (formatted.isNotEmpty) {
          return '$formatted\n\n$_tagline\n$_installLink';
        }
      }
    } catch (_) {}

    return _manualFormat(title, content);
  }

  /// Clean fallback formatting without AI.
  static String _manualFormat(String title, String content) {
    final buf = StringBuffer();

    if (title.isNotEmpty) {
      buf.writeln('📌 $title');
      buf.writeln();
    }

    final lines = content.split('\n').where((l) => l.trim().isNotEmpty);
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('- [') || trimmed.startsWith('•')) {
        buf.writeln(trimmed);
      } else {
        buf.writeln('• $trimmed');
      }
    }

    buf.writeln();
    buf.writeln('⚡ $_tagline');
    buf.write('👉 $_installLink');

    return buf.toString();
  }

  /// Shows a share preview bottom sheet, then shares.
  static Future<void> shareNote(BuildContext context, Note note) async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _SmartShareSheet(note: note),
    );
  }
}

class _SmartShareSheet extends StatefulWidget {
  final Note note;
  const _SmartShareSheet({required this.note});

  @override
  State<_SmartShareSheet> createState() => _SmartShareSheetState();
}

class _SmartShareSheetState extends State<_SmartShareSheet> {
  String? _formatted;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _format();
  }

  Future<void> _format() async {
    final result = await SmartShareService.formatNote(widget.note);
    if (!mounted) return;
    setState(() {
      _formatted = result;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.auto_awesome, color: cs.primary, size: 22),
                const SizedBox(width: 8),
                Text(
                  'Smart Share',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'AI-formatted with your app branding',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Column(
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                      SizedBox(height: 12),
                      Text('Formatting with AI...'),
                    ],
                  ),
                ),
              )
            else ...[
              Container(
                constraints: const BoxConstraints(maxHeight: 280),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cs.outlineVariant.withOpacity(0.5)),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    _formatted ?? '',
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        final raw =
                            '${widget.note.title}\n\n${widget.note.content}'
                                .trim();
                        Share.share(raw, subject: widget.note.title);
                      },
                      icon: const Icon(Icons.text_snippet_outlined, size: 18),
                      label: const Text('Plain'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        Share.share(
                          _formatted ?? '',
                          subject: widget.note.title.isEmpty
                              ? 'AI Sticky Note'
                              : widget.note.title,
                        );
                      },
                      icon:
                          const Icon(Icons.auto_awesome_rounded, size: 18),
                      label: const Text('Share Smart'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
