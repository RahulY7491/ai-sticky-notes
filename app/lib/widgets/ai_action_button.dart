import 'package:flutter/material.dart';

class AiActionButton extends StatelessWidget {
  final VoidCallback onSummarize;
  final VoidCallback onExtractTasks;
  final VoidCallback onGenerateEmail;

  const AiActionButton({
    super.key,
    required this.onSummarize,
    required this.onExtractTasks,
    required this.onGenerateEmail,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_AiAction>(
      icon: const Icon(Icons.smart_toy_outlined),
      tooltip: 'AI Actions',
      onSelected: (action) {
        switch (action) {
          case _AiAction.summarize:
            onSummarize();
            break;
          case _AiAction.extractTasks:
            onExtractTasks();
            break;
          case _AiAction.generateEmail:
            onGenerateEmail();
            break;
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: _AiAction.summarize,
          child: Text('Summarize'),
        ),
        PopupMenuItem(
          value: _AiAction.extractTasks,
          child: Text('Extract Tasks'),
        ),
        PopupMenuItem(
          value: _AiAction.generateEmail,
          child: Text('Generate Email'),
        ),
      ],
    );
  }
}

enum _AiAction { summarize, extractTasks, generateEmail }

