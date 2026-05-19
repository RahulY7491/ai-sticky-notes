import 'package:flutter/material.dart';

import '../models/note.dart';
import '../services/smart_share_service.dart';

class NoteCard extends StatelessWidget {
  final Note note;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  final VoidCallback? onPin;
  final VoidCallback? onUnpin;
  final bool isPinned;
  final String? searchQuery;

  const NoteCard({
    super.key,
    required this.note,
    required this.onTap,
    this.onDelete,
    this.onPin,
    this.onUnpin,
    this.isPinned = false,
    this.searchQuery,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final brightness = theme.brightness;
    final hasReminder = note.reminderTime != null;

    final noteColor = NoteColors.of(note.colorIndex, brightness);
    final hasColor = note.colorIndex > 0;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      elevation: hasColor ? 0 : 1,
      color: hasColor ? noteColor : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: hasColor
            ? BorderSide.none
            : BorderSide(color: cs.outlineVariant.withOpacity(0.3)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title + pinned badge
                    Row(
                      children: [
                        if (isPinned) ...[
                          Icon(Icons.widgets_rounded,
                              size: 14, color: cs.primary),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: _highlightText(
                            note.title.isEmpty ? 'Untitled' : note.title,
                            theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            cs.primary,
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    _highlightText(
                      note.content,
                      theme.textTheme.bodyMedium?.copyWith(
                        color: hasColor ? null : theme.hintColor,
                      ),
                      cs.primary,
                      maxLines: 2,
                    ),
                    if (hasReminder) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: cs.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.alarm, size: 13, color: cs.primary),
                            const SizedBox(width: 4),
                            Text(
                              TimeOfDay.fromDateTime(note.reminderTime!)
                                  .format(context),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: cs.primary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // 3-dot menu
              PopupMenuButton<_CardAction>(
                icon: Icon(Icons.more_vert,
                    size: 20, color: cs.onSurface.withOpacity(0.5)),
                onSelected: (action) {
                  switch (action) {
                    case _CardAction.share:
                      SmartShareService.shareNote(context, note);
                    case _CardAction.pin:
                      onPin?.call();
                    case _CardAction.unpin:
                      onUnpin?.call();
                    case _CardAction.delete:
                      onDelete?.call();
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: _CardAction.share,
                    child: _MenuItem(
                      icon: Icons.auto_awesome_rounded,
                      label: 'Smart Share',
                    ),
                  ),
                  if (!isPinned && onPin != null)
                    const PopupMenuItem(
                      value: _CardAction.pin,
                      child: _MenuItem(
                        icon: Icons.widgets_outlined,
                        label: 'Pin to widget',
                      ),
                    ),
                  if (isPinned && onUnpin != null)
                    const PopupMenuItem(
                      value: _CardAction.unpin,
                      child: _MenuItem(
                        icon: Icons.phonelink_erase_outlined,
                        label: 'Unpin from widget',
                      ),
                    ),
                  if (onDelete != null)
                    const PopupMenuItem(
                      value: _CardAction.delete,
                      child: _MenuItem(
                        icon: Icons.delete_outline,
                        label: 'Delete',
                        isDestructive: true,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Highlights search query matches in the text.
  Widget _highlightText(
    String text,
    TextStyle? style,
    Color highlightColor, {
    int maxLines = 1,
  }) {
    if (searchQuery == null || searchQuery!.isEmpty) {
      return Text(text, style: style, maxLines: maxLines,
          overflow: TextOverflow.ellipsis);
    }

    final query = searchQuery!.toLowerCase();
    final lowerText = text.toLowerCase();
    final spans = <TextSpan>[];
    int start = 0;

    while (true) {
      final idx = lowerText.indexOf(query, start);
      if (idx == -1) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }
      if (idx > start) {
        spans.add(TextSpan(text: text.substring(start, idx)));
      }
      spans.add(TextSpan(
        text: text.substring(idx, idx + query.length),
        style: TextStyle(
          backgroundColor: highlightColor.withOpacity(0.25),
          fontWeight: FontWeight.w700,
        ),
      ));
      start = idx + query.length;
    }

    return RichText(
      text: TextSpan(style: style, children: spans),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }
}

enum _CardAction { share, pin, unpin, delete }

class _MenuItem extends StatelessWidget {
  const _MenuItem({
    required this.icon,
    required this.label,
    this.isDestructive = false,
  });

  final IconData icon;
  final String label;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final color = isDestructive
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.onSurface;
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 12),
        Text(label, style: TextStyle(color: color)),
      ],
    );
  }
}
