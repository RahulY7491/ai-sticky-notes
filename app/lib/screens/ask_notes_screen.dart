import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/note.dart';
import '../services/ai_service.dart';
import '../services/usage_gate.dart';
import '../utils/week_plan_window.dart';
import 'home_screen.dart';

// ─────────────────────────────────────────────────────────────
// Chat message model
// ─────────────────────────────────────────────────────────────

enum _Role { user, assistant }

class _Message {
  final _Role role;
  final String text;
  final bool isLoading;

  const _Message({required this.role, required this.text, this.isLoading = false});
}

// ─────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────

class AskNotesScreen extends StatefulWidget {
  const AskNotesScreen({super.key});

  @override
  State<AskNotesScreen> createState() => _AskNotesScreenState();
}

class _AskNotesScreenState extends State<AskNotesScreen> {
  final _controller = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _messages = <_Message>[];
  bool _isProcessing = false;

  @override
  void dispose() {
    _controller.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final query = _controller.text.trim();
    if (query.isEmpty || _isProcessing) return;

    if (!await UsageGate.instance.guardAiAction(context)) return;
    if (!mounted) return;

    _controller.clear();
    setState(() {
      _messages.add(_Message(role: _Role.user, text: query));
      _messages.add(const _Message(role: _Role.assistant, text: '', isLoading: true));
      _isProcessing = true;
    });
    _scrollToBottom();

    try {
      final provider = context.read<NotesProvider>();
      final now = DateTime.now();

      final List<Note> sourceNotes;
      final String? scopeInstruction;
      if (looksLikeWeekPlanQuestion(query)) {
        final window = thisWeekThroughNextSaturday(now);
        sourceNotes = filterNotesForWeekPlan(provider.notes, window);
        scopeInstruction =
            'Special scope — THIS WEEK ONLY (${window.describe()}, local dates): '
            'These notes are pre-filtered. Include ONLY items whose reminder falls '
            'from the start of today through the end of that Saturday, inclusive. '
            'Ignore anything before today and anything scheduled after that Saturday. '
            'Notes without a reminder appear here only if created or updated on or after today; '
            'still treat their content as current-week context. '
            'Group by day when it helps.';
      } else {
        sourceNotes = List<Note>.from(provider.notes);
        scopeInstruction = null;
      }

      final notePayload = sourceNotes.map((n) {
        return {
          'title': n.title,
          'content': n.content,
          'date': _formatDate(n.createdAt),
          'reminder': n.reminderTime != null ? _formatDate(n.reminderTime!) : '',
        };
      }).toList();

      final answer = await AiService.instance.askNotes(
        notes: notePayload,
        query: query,
        scopeInstruction: scopeInstruction,
      );

      if (!mounted) return;
      setState(() {
        _messages.removeLast(); // remove loading bubble
        _messages.add(_Message(role: _Role.assistant, text: answer));
        _isProcessing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.removeLast();
        _messages.add(
          const _Message(
            role: _Role.assistant,
            text: "Sorry, I couldn't search your notes right now. Please try again.",
          ),
        );
        _isProcessing = false;
      });
    }
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent + 80,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  static String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final p = dt.hour < 12 ? 'AM' : 'PM';
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}, $h:$m $p';
  }

  // ── Quick suggestions ──────────────────────────────────────

  static const _suggestions = [
    'What is my this week plan?',
    'Show pending tasks',
    'Any reminders coming up?',
    'Summarize my recent notes',
  ];

  void _useSuggestion(String text) {
    _controller.text = text;
    _send();
  }

  // ── Build ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.forum_outlined, color: cs.primary, size: 22),
            const SizedBox(width: 8),
            const Text('Ask Your Notes'),
          ],
        ),
      ),
      body: Column(
        children: [
          // ── Chat messages ────────────────────────────────
          Expanded(
            child: _messages.isEmpty
                ? _EmptyState(
                    cs: cs,
                    theme: theme,
                    suggestions: _suggestions,
                    onSuggestion: _useSuggestion,
                  )
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) => _ChatBubble(
                      message: _messages[i],
                      cs: cs,
                      theme: theme,
                    ),
                  ),
          ),

          // ── Input bar ────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: cs.surface,
              border: Border(top: BorderSide(color: cs.outline.withOpacity(0.15))),
            ),
            padding: EdgeInsets.only(
              left: 16,
              right: 8,
              top: 8,
              bottom: MediaQuery.of(context).viewInsets.bottom + 8,
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: 'Ask anything about your notes…',
                        hintStyle: TextStyle(color: cs.onSurfaceVariant.withOpacity(0.6)),
                        filled: true,
                        fillColor: cs.surfaceVariant.withOpacity(0.4),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filled(
                    onPressed: _isProcessing ? null : _send,
                    icon: _isProcessing
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: cs.onPrimary,
                            ),
                          )
                        : const Icon(Icons.send_rounded, size: 20),
                    style: IconButton.styleFrom(
                      backgroundColor: cs.primary,
                      foregroundColor: cs.onPrimary,
                      disabledBackgroundColor: cs.primary.withOpacity(0.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Empty state with suggestions
// ─────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.cs,
    required this.theme,
    required this.suggestions,
    required this.onSuggestion,
  });

  final ColorScheme cs;
  final ThemeData theme;
  final List<String> suggestions;
  final void Function(String) onSuggestion;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.psychology_outlined,
                size: 56, color: cs.primary.withOpacity(0.6)),
            const SizedBox(height: 16),
            Text(
              'Chat with your memory',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Ask questions and I\'ll search all your notes to find the answer.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            Text(
              'Try asking:',
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: suggestions
                  .map(
                    (s) => ActionChip(
                      label: Text(s, style: const TextStyle(fontSize: 13)),
                      avatar: Icon(Icons.auto_awesome, size: 15, color: cs.primary),
                      onPressed: () => onSuggestion(s),
                      backgroundColor: cs.primaryContainer.withOpacity(0.4),
                      side: BorderSide(color: cs.outline.withOpacity(0.15)),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Chat bubble
// ─────────────────────────────────────────────────────────────

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({
    required this.message,
    required this.cs,
    required this.theme,
  });

  final _Message message;
  final ColorScheme cs;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == _Role.user;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: cs.primaryContainer,
              child: Icon(Icons.psychology, size: 18, color: cs.primary),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser
                    ? cs.primary
                    : cs.surfaceVariant.withOpacity(0.55),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isUser ? 16 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 16),
                ),
              ),
              child: message.isLoading
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Searching your notes…',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    )
                  : SelectableText(
                      message.text,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: isUser ? cs.onPrimary : cs.onSurface,
                        height: 1.45,
                      ),
                    ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 16,
              backgroundColor: cs.primary,
              child: Icon(Icons.person, size: 18, color: cs.onPrimary),
            ),
          ],
        ],
      ),
    );
  }
}
