import 'dart:convert';

import 'package:ai_sticky_notes/widgets/voice_note_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// Channel used by the speech_to_text plugin (see
/// `method_channel_speech_to_text.dart` in
/// `speech_to_text_platform_interface`). All platform calls performed by
/// `VoiceNoteSheet` go through this channel, so mocking it lets us drive the
/// widget through every phase deterministically without needing a real device
/// or microphone.
const _speechChannelName = 'plugin.csdcorp.com/speech_to_text';
const _speechChannel = MethodChannel(_speechChannelName);

/// Production code uses `stt.SpeechToText()` which is a process-wide
/// singleton; once `_initWorked` flips to true it never re-registers
/// listeners on subsequent `initialize()` calls, so a second test would see
/// platform callbacks routed to the previous (disposed) sheet. The widget
/// accepts a `speechFactory` so tests can hand in a fresh instance per sheet.
stt.SpeechToText _freshSpeech() => stt.SpeechToText.withMethodChannel();

/// `VoiceNoteSheet` runs a continuously-repeating pulse animation while it is
/// alive, so `pumpAndSettle` never returns. Use this helper instead — it
/// advances fake time in small slices so widget state, timers, and the
/// AnimatedSwitcher between phases all progress.
Future<void> _advance(
  WidgetTester tester, [
  Duration total = const Duration(seconds: 2),
]) async {
  const step = Duration(milliseconds: 50);
  var elapsed = Duration.zero;
  while (elapsed < total) {
    await tester.pump(step);
    elapsed += step;
  }
}

/// Tear the widget down inside the test body and pump enough fake time so any
/// pending `_notifyFinalTimer` (2 s) scheduled by an in-flight `_speech.stop()`
/// fires (or, if the completer is still open, that a generous buffer covers
/// the engine's `_listenTimer`) before the framework's pending-timer
/// assertion runs at the end of the test. Tests that enter the listening
/// phase should ensure the transcript completer is completed first (via
/// tapping the mic, emitting a final transcript, etc.) so this helper does
/// not have to wait the full 20-second `Future.timeout`.
Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
  await tester.pump(const Duration(seconds: 3));
}

/// Builds a host that exposes a button which opens the [VoiceNoteSheet] and
/// captures whatever it returns into [resultBox] for later assertions.
Widget _hostApp(List<VoiceNoteResult?> resultBox) {
  return MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () async {
              final r = await VoiceNoteSheet.show(
                context,
                speechFactory: _freshSpeech,
              );
              resultBox.add(r);
            },
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
}

/// Sends a fake platform → app message on the speech_to_text channel so the
/// plugin's internal handler (registered during `initialize`) fires exactly
/// like the native side would.
Future<void> _emitPlatformCall(String method, dynamic arguments) async {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  await messenger.handlePlatformMessage(
    _speechChannelName,
    const StandardMethodCodec()
        .encodeMethodCall(MethodCall(method, arguments)),
    (_) {},
  );
}

/// Configures mock responses for the speech_to_text channel. Pass
/// [initializeReturns] to control whether the engine is reported as
/// available; pass [listenReturns] to control whether `listen` succeeds.
void _mockSpeechChannel({
  bool initializeReturns = true,
  bool listenReturns = true,
}) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_speechChannel, (call) async {
    switch (call.method) {
      case 'initialize':
        return initializeReturns;
      case 'listen':
        return listenReturns;
      case 'stop':
      case 'cancel':
      case 'has_permission':
        return null;
      case 'locales':
        return <dynamic>[];
      default:
        return null;
    }
  });
}

void _clearSpeechChannel() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_speechChannel, null);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(_clearSpeechChannel);

  group('VoiceNoteSheet error states', () {
    testWidgets(
      'shows "not available" error when speech engine fails to initialize',
      (tester) async {
        _mockSpeechChannel(initializeReturns: false);

        await tester.pumpWidget(_hostApp([]));
        await tester.tap(find.text('Open'));
        await _advance(tester);

        expect(
          find.text('Voice input is not available on this device.'),
          findsOneWidget,
        );
        expect(find.text('Try again'), findsOneWidget);
        expect(find.text('Dismiss'), findsOneWidget);
        expect(find.byIcon(Icons.mic_off_outlined), findsOneWidget);
      },
    );

    testWidgets('Dismiss closes the sheet and returns null', (tester) async {
      _mockSpeechChannel(initializeReturns: false);

      final results = <VoiceNoteResult?>[];
      await tester.pumpWidget(_hostApp(results));
      await tester.tap(find.text('Open'));
      await _advance(tester);

      await tester.tap(find.text('Dismiss'));
      await _advance(tester);

      expect(find.text('Voice input is not available on this device.'),
          findsNothing);
      expect(results, hasLength(1));
      expect(results.single, isNull);
    });

    testWidgets('Try again resets and re-attempts capture', (tester) async {
      _mockSpeechChannel(initializeReturns: false);

      await tester.pumpWidget(_hostApp([]));
      await tester.tap(find.text('Open'));
      await _advance(tester);

      expect(find.text('Voice input is not available on this device.'),
          findsOneWidget);

      _mockSpeechChannel(initializeReturns: true);

      await tester.tap(find.text('Try again'));
      await _advance(tester, const Duration(milliseconds: 600));

      expect(find.text('Listening…'), findsOneWidget);
      expect(find.text('Tap to stop'), findsOneWidget);
      expect(find.text('Say something…'), findsOneWidget);

      // Drain the open transcript completer + 2-second `_notifyFinalTimer`
      // before disposing.
      await tester.tap(find.byIcon(Icons.mic));
      await _advance(tester, const Duration(seconds: 4));

      await _teardown(tester);
    });
  });

  group('VoiceNoteSheet listening flow', () {
    testWidgets(
      'shows listening UI with countdown when engine is available',
      (tester) async {
        _mockSpeechChannel();

        await tester.pumpWidget(_hostApp([]));
        await tester.tap(find.text('Open'));
        // Stay below the 1-second mark so the countdown hasn't ticked yet.
        await _advance(tester, const Duration(milliseconds: 600));

        expect(find.text('Listening…'), findsOneWidget);
        expect(find.text('15s'), findsOneWidget);
        expect(find.byIcon(Icons.mic), findsOneWidget);
        expect(find.byType(LinearProgressIndicator), findsOneWidget);

        // Drain the completer + finalTimer before disposing.
        await tester.tap(find.byIcon(Icons.mic));
        await _advance(tester, const Duration(seconds: 4));

        await _teardown(tester);
      },
    );

    testWidgets(
      'tap-to-stop with no transcript shows "Didn\'t catch that" error',
      (tester) async {
        _mockSpeechChannel();

        await tester.pumpWidget(_hostApp([]));
        await tester.tap(find.text('Open'));
        await _advance(tester, const Duration(milliseconds: 600));

        expect(find.text('Listening…'), findsOneWidget);

        // Tap the mic to stop — `_stopListening` completes the transcript
        // completer with the (empty) live text directly.
        await tester.tap(find.byIcon(Icons.mic));
        await _advance(tester, const Duration(seconds: 4));

        expect(
          find.textContaining("Didn't catch that"),
          findsOneWidget,
        );
        expect(find.text('Try again'), findsOneWidget);

        await _teardown(tester);
      },
    );

    testWidgets(
      'final transcript triggers AI processing then shows error when no API key',
      (tester) async {
        _mockSpeechChannel();

        await tester.pumpWidget(_hostApp([]));
        await tester.tap(find.text('Open'));
        await _advance(tester, const Duration(milliseconds: 600));

        // SpeechRecognitionResult.fromJson expects this exact shape.
        await _emitPlatformCall(
          'textRecognition',
          jsonEncode({
            'alternates': [
              {'recognizedWords': 'buy milk tomorrow', 'confidence': 0.9},
            ],
            'finalResult': true,
          }),
        );
        await _advance(tester, const Duration(seconds: 4));

        // Without a GEMINI_API_KEY at compile time, AiService.voiceToNote
        // throws and the widget lands in the error phase.
        expect(
          find.textContaining('Could not create note'),
          findsOneWidget,
        );
        expect(find.text('Try again'), findsOneWidget);

        await _teardown(tester);
      },
    );
  });
}
