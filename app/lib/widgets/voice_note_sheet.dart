import 'dart:async';

import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../models/note.dart';
import '../services/ai_service.dart';
import '../services/security_service.dart';
import '../services/usage_gate.dart';

/// All phases the voice capture can be in.
enum _Phase { init, listening, processing, preview, error }

/// Result returned to the caller when the sheet closes.
typedef VoiceNoteResult = ({String action, Note note});

/// Google Keep–style voice capture bottom sheet.
///
/// Usage:
///   final result = await VoiceNoteSheet.show(context);
///   if (result != null) { /* result.action == 'save' | 'edit' */ }
class VoiceNoteSheet extends StatefulWidget {
  const VoiceNoteSheet._({this.speechFactory});

  /// Optional factory for the underlying [stt.SpeechToText] instance. Used
  /// only by tests to inject a fresh instance per sheet — the
  /// `speech_to_text` package exposes a process-wide singleton that retains
  /// listener references across instances, which makes per-test isolation
  /// impossible without this seam. Production callers leave it null and the
  /// default singleton is used.
  final stt.SpeechToText Function()? speechFactory;

  static Future<VoiceNoteResult?> show(
    BuildContext context, {
    stt.SpeechToText Function()? speechFactory,
  }) =>
      showModalBottomSheet<VoiceNoteResult>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        enableDrag: false,
        builder: (_) => VoiceNoteSheet._(speechFactory: speechFactory),
      );

  @override
  State<VoiceNoteSheet> createState() => _VoiceNoteSheetState();
}

class _VoiceNoteSheetState extends State<VoiceNoteSheet>
    with SingleTickerProviderStateMixin {
  static const _maxSeconds = 15;

  // ── Speech engine ──────────────────────────────────────────
  late final stt.SpeechToText _speech =
      widget.speechFactory?.call() ?? stt.SpeechToText();
  Completer<String>? _transcriptCompleter;

  // ── State ───────────────────────────────────────────────────
  _Phase _phase = _Phase.init;
  String _liveText = '';
  String? _errorMessage;
  String? _aiTitle;
  String? _aiBody;

  // ── Countdown timer ────────────────────────────────────────
  Timer? _countdownTimer;
  int _secondsLeft = _maxSeconds;

  // ── Animation ───────────────────────────────────────────────
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulse;
  late final Animation<double> _ring;

  // ── Lifecycle ───────────────────────────────────────────────

  @override
  void initState() {
    super.initState();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _pulse = Tween<double>(begin: 1.0, end: 1.18).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _ring = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) => _startCapture());
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _pulseCtrl.dispose();
    // `cancel()` shuts the engine down without scheduling the 2-second
    // `_notifyFinalTimer` that `stop()` queues from its async continuation.
    // Since the widget is going away there's nothing to finalize.
    _speech.cancel();
    super.dispose();
  }

  // ── Core flow ───────────────────────────────────────────────

  Future<void> _startCapture() async {
    bool available = false;
    try {
      available = await _speech.initialize(
        onError: (err) {
          SecurityService.log('Voice', 'error: $err');
          if (err.permanent && mounted) _setError('Voice input unavailable.');
        },
        onStatus: (status) {
          SecurityService.log('Voice', 'status: $status');
          // Native recogniser stopped — resolve the completer so we proceed.
          if ((status == 'done' || status == 'notListening') &&
              !(_transcriptCompleter?.isCompleted ?? true)) {
            _transcriptCompleter!.complete(_liveText);
          }
        },
      );
    } catch (_) {
      available = false;
    }

    if (!mounted) return;

    if (!available) {
      _setError('Voice input is not available on this device.');
      return;
    }

    final systemLocale = await _speech.systemLocale();
    if (!mounted) return;

    setState(() {
      _phase = _Phase.listening;
      _secondsLeft = _maxSeconds;
    });
    _transcriptCompleter = Completer<String>();

    // Start visible countdown.
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) {
        timer.cancel();
        _stopListening();
      }
    });

    await _speech.listen(
      onResult: (result) {
        if (!mounted) return;
        setState(() => _liveText = result.recognizedWords);
        if (result.finalResult &&
            !(_transcriptCompleter?.isCompleted ?? true)) {
          _transcriptCompleter!.complete(result.recognizedWords);
        }
      },
      onSoundLevelChange: (_) {},
      listenFor: const Duration(seconds: _maxSeconds + 2),
      pauseFor: const Duration(seconds: 10),
      localeId: systemLocale?.localeId,
    );

    // Await transcript; timeout is a safety net only.
    final raw = await _transcriptCompleter!.future.timeout(
      const Duration(seconds: _maxSeconds + 5),
      onTimeout: () => _liveText,
    );

    await _speech.stop();
    if (!mounted) return;

    final transcript = raw.trim();
    if (transcript.isEmpty) {
      _setError("Didn't catch that. Tap 'Try again' to record.");
      return;
    }

    await _runAi(transcript);
  }

  Future<void> _runAi(String transcript) async {
    if (!mounted) return;

    if (!await UsageGate.instance.guardAiAction(context)) {
      if (mounted) Navigator.of(context).pop();
      return;
    }

    setState(() => _phase = _Phase.processing);

    try {
      final structured = await AiService.instance.voiceToNote(transcript);
      if (!mounted) return;
      setState(() {
        _aiTitle = structured['title'];
        _aiBody = structured['body'];
        _phase = _Phase.preview;
      });
    } catch (_) {
      if (!mounted) return;
      _setError('Could not create note. Check your connection and try again.');
    }
  }

  void _stopListening() {
    _countdownTimer?.cancel();
    _speech.stop();
    if (!(_transcriptCompleter?.isCompleted ?? true)) {
      _transcriptCompleter!.complete(_liveText);
    }
  }

  Future<void> _retry() async {
    _countdownTimer?.cancel();
    setState(() {
      _phase = _Phase.init;
      _liveText = '';
      _secondsLeft = _maxSeconds;
      _errorMessage = null;
      _aiTitle = null;
      _aiBody = null;
    });
    await _startCapture();
  }

  void _setError(String msg) {
    if (!mounted) return;
    setState(() {
      _phase = _Phase.error;
      _errorMessage = msg;
    });
  }

  Note _buildNote() {
    final now = DateTime.now();
    return Note(
      title: _aiTitle ?? _liveText,
      content: _aiBody ?? _liveText,
      createdAt: now,
      updatedAt: now,
    );
  }

  // ── UI ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 28,
        left: 24,
        right: 24,
        top: 12,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 24),
            decoration: BoxDecoration(
              color: cs.onSurfaceVariant.withOpacity(0.35),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: KeyedSubtree(
              key: ValueKey(_phase),
              child: _buildPhase(theme, cs),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhase(ThemeData theme, ColorScheme cs) {
    switch (_phase) {
      case _Phase.init:
        return _InitView(cs: cs);
      case _Phase.listening:
        return _ListeningView(
          cs: cs,
          theme: theme,
          liveText: _liveText,
          secondsLeft: _secondsLeft,
          maxSeconds: _maxSeconds,
          pulse: _pulse,
          ring: _ring,
          onStop: _stopListening,
        );
      case _Phase.processing:
        return _ProcessingView(cs: cs);
      case _Phase.preview:
        return _PreviewView(
          theme: theme,
          cs: cs,
          title: _aiTitle ?? '',
          body: _aiBody ?? '',
          onDiscard: () => Navigator.of(context).pop(null),
          onEdit: () => Navigator.of(context).pop((action: 'edit', note: _buildNote())),
          onSave: () => Navigator.of(context).pop((action: 'save', note: _buildNote())),
        );
      case _Phase.error:
        return _ErrorView(
          theme: theme,
          cs: cs,
          message: _errorMessage ?? 'Something went wrong.',
          onRetry: _retry,
          onClose: () => Navigator.of(context).pop(null),
        );
    }
  }
}

// ─────────────────────────────────────────────────────────────
// Phase sub-widgets (each is a pure display widget)
// ─────────────────────────────────────────────────────────────

class _InitView extends StatelessWidget {
  const _InitView({required this.cs});
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator(color: cs.primary)),
      );
}

class _ListeningView extends StatelessWidget {
  const _ListeningView({
    required this.cs,
    required this.theme,
    required this.liveText,
    required this.secondsLeft,
    required this.maxSeconds,
    required this.pulse,
    required this.ring,
    required this.onStop,
  });

  final ColorScheme cs;
  final ThemeData theme;
  final String liveText;
  final int secondsLeft;
  final int maxSeconds;
  final Animation<double> pulse;
  final Animation<double> ring;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final progress = secondsLeft / maxSeconds; // 1.0 → 0.0

    return Column(
      children: [
        // Header: "Listening…" + countdown
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Listening…',
              style: theme.textTheme.titleMedium
                  ?.copyWith(color: cs.primary, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 10),
            Text(
              '${secondsLeft}s',
              style: theme.textTheme.titleMedium?.copyWith(
                color: secondsLeft <= 3 ? cs.error : cs.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),

        // Progress bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 4,
              backgroundColor: cs.surfaceVariant,
              valueColor: AlwaysStoppedAnimation<Color>(
                secondsLeft <= 3 ? cs.error : cs.primary,
              ),
            ),
          ),
        ),

        const SizedBox(height: 24),

        // Pulsing mic with outer ring
        GestureDetector(
          onTap: onStop,
          child: SizedBox(
            width: 120,
            height: 120,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Outer glow ring
                AnimatedBuilder(
                  animation: ring,
                  builder: (_, __) => Container(
                    width: 120 * ring.value,
                    height: 120 * ring.value,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: cs.primary.withOpacity(0.15 * ring.value),
                    ),
                  ),
                ),
                // Inner pulsing button
                ScaleTransition(
                  scale: pulse,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: cs.primary,
                      boxShadow: [
                        BoxShadow(
                          color: cs.primary.withOpacity(0.45),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Icon(Icons.mic, color: cs.onPrimary, size: 34),
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 8),
        Text(
          'Tap to stop',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: cs.onSurfaceVariant),
        ),

        const SizedBox(height: 24),

        // Live transcript bubble
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: cs.surfaceVariant.withOpacity(0.45),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            liveText.isEmpty ? 'Say something…' : liveText,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: liveText.isEmpty ? cs.onSurfaceVariant : cs.onSurface,
              height: 1.45,
            ),
            textAlign: TextAlign.center,
          ),
        ),

        const SizedBox(height: 4),
      ],
    );
  }
}

class _ProcessingView extends StatelessWidget {
  const _ProcessingView({required this.cs});
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 200,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: cs.primary),
            const SizedBox(height: 20),
            Text(
              'Creating your note…',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
            ),
          ],
        ),
      );
}

class _PreviewView extends StatelessWidget {
  const _PreviewView({
    required this.theme,
    required this.cs,
    required this.title,
    required this.body,
    required this.onDiscard,
    required this.onEdit,
    required this.onSave,
  });

  final ThemeData theme;
  final ColorScheme cs;
  final String title;
  final String body;
  final VoidCallback onDiscard;
  final VoidCallback onEdit;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.auto_awesome, size: 18),
            const SizedBox(width: 8),
            Text(
              'Voice note created',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Note preview card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cs.surfaceVariant.withOpacity(0.45),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.outline.withOpacity(0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              if (body.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  body,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: cs.onSurfaceVariant, height: 1.4),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 24),

        // Actions
        Row(
          children: [
            TextButton(
              onPressed: onDiscard,
              child: Text('Discard',
                  style: TextStyle(color: cs.onSurfaceVariant)),
            ),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Edit'),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: cs.outline),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: onSave,
              icon: const Icon(Icons.check, size: 16),
              label: const Text('Save'),
            ),
          ],
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.theme,
    required this.cs,
    required this.message,
    required this.onRetry,
    required this.onClose,
  });

  final ThemeData theme;
  final ColorScheme cs;
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 210,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.mic_off_outlined, size: 44, color: cs.error),
          const SizedBox(height: 14),
          Text(
            message,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: cs.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton(
                onPressed: onClose,
                child: const Text('Dismiss'),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Try again'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
