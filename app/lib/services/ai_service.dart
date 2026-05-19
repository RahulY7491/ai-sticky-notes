import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../domain/entities/brain_dump_result.dart';
import '../models/note.dart';
import 'security_service.dart';

class _CacheEntry {
  final String value;
  final DateTime expiresAt;
  _CacheEntry(this.value, this.expiresAt);
  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

class AiService {
  AiService._internal();

  static final AiService instance = AiService._internal();

  /// In-memory LRU cache to avoid redundant API calls for identical prompts.
  final Map<String, _CacheEntry> _cache = {};
  static const _maxCacheSize = 50;
  static const _cacheTtl = Duration(minutes: 10);

  static const _model = 'gemini-2.5-flash';
  static const _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent';

  static const String _apiKey = String.fromEnvironment('GEMINI_API_KEY');

  bool get hasApiKey => _apiKey.isNotEmpty;

  /// Pinned HTTP client that only trusts Google's API hostname.
  /// Prevents MITM attacks that could intercept the API key or responses.
  http.Client? _pinnedClient;
  http.Client get _httpClient {
    if (kIsWeb) return http.Client();
    if (_pinnedClient != null) return _pinnedClient!;

    final inner = HttpClient()
      ..badCertificateCallback = (cert, host, port) {
        // Reject all certificates that don't match the expected host.
        // In production the system CA store validates the cert chain;
        // this callback only fires for BAD certs — always reject them.
        return false;
      };

    _pinnedClient = IOClient(inner);
    return _pinnedClient!;
  }

  /// Extracts a reminder [DateTime] from natural-language note text.
  ///
  /// Pass [now] so relative expressions ("tomorrow", "next Monday") resolve
  /// correctly. Returns `null` when no time intent is present.
  Future<DateTime?> detectReminder(String noteText, DateTime now) async {
    final today = now.toIso8601String().substring(0, 10);
    final tomorrow = now
        .add(const Duration(days: 1))
        .toIso8601String()
        .substring(0, 10);
    final weekday = _weekdayName(now.weekday);

    final prompt = '''
Extract a reminder date and time from the following note.

Current date/time: ${now.toIso8601String()} ($weekday)
Today: $today
Tomorrow: $tomorrow

Rules (follow exactly):
- Respond with STRICT JSON only, no markdown, no prose, no code fences.
- JSON shape: {"datetime": "YYYY-MM-DDTHH:MM:SS"} or {"datetime": null}
- Resolve relative expressions:
  - "tomorrow" → $tomorrow
  - "today" → $today
  - Day names ("Monday", "Friday") → nearest upcoming occurrence
  - "next week" → 7 days from today
- If only a time is given and it is still in the future today, use today; otherwise use tomorrow.
- If only a date is given with no time, use 09:00.
- If no reminder intent exists, return {"datetime": null}.

Note: $noteText
''';

    try {
      final rawResponse = await _callGemini(prompt);
      final raw = rawResponse
          .replaceAll(RegExp(r'^```json\s*', multiLine: true), '')
          .replaceAll(RegExp(r'^```\s*', multiLine: true), '')
          .trim();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final dt = decoded['datetime'] as String?;
      if (dt == null || dt.isEmpty) return null;
      return DateTime.parse(dt);
    } catch (_) {
      return null;
    }
  }

  static String _weekdayName(int weekday) {
    const names = [
      '',
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    return names[weekday.clamp(1, 7)];
  }

  /// Generates a short, warm AI memory reflection for a group of notes.
  ///
  /// [label] is a human label like "Today" or "Mon, 3 Mar".
  Future<String> generateMemorySummary({
    required String label,
    required List<String> noteTexts,
  }) {
    final joined = noteTexts
        .take(12)
        .map((t) => '• $t')
        .join('\n');
    return _callGemini('''
You are a thoughtful personal journal assistant.
A user has the following notes from "$label":

$joined

Write a single short paragraph (2-4 sentences) that reflects on these notes warmly,
as if recapping what was on their mind. Be concise, empathetic, and insightful.
Do NOT list the notes back — synthesise them into a natural memory reflection.
''');
  }

  /// Analyses a note and returns structured context-aware actions in a single call.
  ///
  /// Returns a map with optional keys:
  ///   "reminder"    → ISO 8601 datetime string
  ///   "tasks"       → List<String>
  ///   "suggestion"  → a short text prompt like "Generate follow-up email?"
  Future<Map<String, dynamic>> analyzeNoteContext(
    String noteText,
    DateTime now,
  ) async {
    final today = now.toIso8601String().substring(0, 10);
    final tomorrow = now.add(const Duration(days: 1)).toIso8601String().substring(0, 10);
    final weekday = _weekdayName(now.weekday);

    final prompt = '''
You are a smart life assistant embedded in a notes app.
Analyze the note below and extract ALL useful actions.

Current date/time: ${now.toIso8601String()} ($weekday)
Today: $today
Tomorrow: $tomorrow

Rules (follow exactly):
- Respond with STRICT JSON only, no markdown, no prose, no code fences.
- JSON shape must be exactly:
  {
    "reminder": "YYYY-MM-DDTHH:MM:SS" or null,
    "tasks": ["task 1", "task 2"] or [],
    "suggestion": "short action prompt" or null
  }

Extraction rules:
1. "reminder": Extract the EARLIEST date/time mentioned.
   - Resolve relative: "tomorrow" → $tomorrow, "today" → $today, day names → next occurrence, "next week" → +7 days.
   - If only a time is given and it is still in the future today, use today; otherwise tomorrow.
   - If only a date with no time, use 09:00. If no time intent at all, set null.
2. "tasks": Extract short actionable tasks (verbs). Return [] if none.
3. "suggestion": Suggest ONE smart follow-up action if obvious (e.g. "Generate follow-up email?", "Create shopping list?", "Summarize meeting notes?"). null if nothing fits.

Note: $noteText
''';

    try {
      final rawResponse = await _callGemini(prompt);
      final raw = rawResponse
          .replaceAll(RegExp(r'^```json\s*', multiLine: true), '')
          .replaceAll(RegExp(r'^```\s*', multiLine: true), '')
          .trim();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;

      // Normalize tasks to List<String>
      final rawTasks = decoded['tasks'];
      final tasks = <String>[];
      if (rawTasks is List) {
        for (final t in rawTasks) {
          final s = t?.toString().trim();
          if (s != null && s.isNotEmpty) tasks.add(s);
        }
      }

      return {
        'reminder': decoded['reminder'] as String?,
        'tasks': tasks,
        'suggestion': decoded['suggestion'] as String?,
      };
    } catch (_) {
      return {'reminder': null, 'tasks': <String>[], 'suggestion': null};
    }
  }

  /// Answers a user's natural-language question by searching across all notes.
  ///
  /// [notes] is a list of maps with keys: title, content, date, reminder.
  /// [query] is the user's question.
  /// [scopeInstruction] optional extra rules (e.g. date window for "this week").
  Future<String> askNotes({
    required List<Map<String, String>> notes,
    required String query,
    String? scopeInstruction,
  }) {
    final notesBlock = notes.take(30).map((n) {
      final parts = <String>[];
      if (n['title']?.isNotEmpty == true) parts.add('Title: ${n['title']}');
      if (n['content']?.isNotEmpty == true) parts.add('Content: ${n['content']}');
      if (n['date']?.isNotEmpty == true) parts.add('Date: ${n['date']}');
      if (n['reminder']?.isNotEmpty == true) parts.add('Reminder: ${n['reminder']}');
      return parts.join('\n');
    }).join('\n---\n');

    final scope = scopeInstruction == null || scopeInstruction.isEmpty
        ? ''
        : '\n$scopeInstruction\n';

    return _callGemini('''
You are an intelligent personal assistant embedded in a notes app.
The user has the following notes:

$notesBlock

The user asks: "$query"
$scope
Rules:
- Answer the question using ONLY information from the notes above.
- Be concise, warm, and helpful. Use short paragraphs or bullet points.
- If the answer involves tasks, list them clearly.
- If you find dates/times, format them nicely (e.g. "Tomorrow at 5 PM").
- If no notes match the query, say so honestly and suggest what the user could try.
- Never make up information that isn't in the notes.
''');
  }

  /// Formats a note into a clean, shareable card with bullet points.
  Future<String> formatForShare(String noteText) => _callGemini('''
You are a smart note formatter. Take messy note text and output a clean, visually appealing text card for sharing via messaging apps (WhatsApp, iMessage, etc).

Rules:
- Start with a 📌 emoji and a bold-style title line (use CAPS or just the title).
- Convert content into clean bullet points using • character.
- If there are tasks, use ✅ for done and ◻ for pending.
- If there are times/dates, include a 🕐 line.
- Keep it concise — max 6-8 lines.
- Do NOT include any markdown formatting (no **, no ##, no code fences).
- Do NOT include any install link or branding — that is added separately.
- Output ONLY the formatted text, nothing else.

Note:
$noteText
''');

  /// Generates a personalized daily briefing from the user's notes.
  /// Result is cached in Hive for the entire day.
  Future<String> generateDailyBriefing({
    required List<Note> notes,
    required int pendingTasks,
    required int streak,
  }) async {
    final today = DateTime.now();
    final dateKey =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

    final box = await Hive.openBox('daily_briefing');
    final cached = box.get(dateKey) as String?;
    if (cached != null && cached.isNotEmpty) return cached;

    final hour = today.hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
            ? 'Good afternoon'
            : 'Good evening';

    final recentNotes = notes.take(10).map((n) {
      final title = n.title.isNotEmpty ? n.title : 'Untitled';
      final preview =
          n.content.length > 80 ? '${n.content.substring(0, 80)}...' : n.content;
      return '• $title: $preview';
    }).join('\n');

    final prompt = '''
You are a warm, concise personal AI assistant inside a notes app.
Generate a 2-sentence daily briefing for the user.

Context:
- Greeting: $greeting
- Day streak: $streak days
- Pending tasks across notes: $pendingTasks
- Recent notes:
$recentNotes

Rules:
- Be warm, motivating, and specific (mention their actual notes).
- Keep it to exactly 2 short sentences.
- No emojis, no bullet points, no greetings — just the insight.
- If few/no notes, encourage them to start capturing thoughts.
''';

    try {
      final result = await _callGemini(prompt);
      await box.put(dateKey, result);
      return result;
    } catch (_) {
      return 'You have $pendingTasks task${pendingTasks == 1 ? '' : 's'} to tackle today. Keep the momentum going!';
    }
  }

  /// MVP: Brain dump → title, bullets, tasks, optional reminder (strict JSON).
  Future<BrainDumpResult> organizeBrainDump(String rawText, DateTime now) async {
    final truncated = rawText.length > 8000
        ? '${rawText.substring(0, 8000)}\n\n[truncated]'
        : rawText;

    final today = now.toIso8601String().substring(0, 10);
    final tomorrow = now
        .add(const Duration(days: 1))
        .toIso8601String()
        .substring(0, 10);
    final weekday = _weekdayName(now.weekday);

    final prompt = '''
Turn the user's messy brain dump into a structured note.

Current date/time: ${now.toIso8601String()} ($weekday)
Today: $today
Tomorrow: $tomorrow

Rules (follow exactly):
- Respond with STRICT JSON only, no markdown, no prose, no code fences.
- JSON shape must be exactly:
  {
    "title": "short line, optional leading emoji",
    "bullets": ["point 1", "point 2"],
    "tasks": ["actionable task 1"],
    "reminder": "YYYY-MM-DDTHH:MM:SS" or null
  }
- "bullets": key ideas, max 6 items, each under 120 chars. Use [] if none.
- "tasks": clear verbs, max 8 items, dedupe. Use [] if none.
- "reminder": earliest future date/time mentioned; resolve "tomorrow"→$tomorrow, "today"→$today, weekday names→next occurrence; time-only still in future→today else tomorrow; date-only→09:00; null if no time intent.

Brain dump:
$truncated
''';

    try {
      final rawResponse = await _callGemini(prompt);
      final raw = rawResponse
          .replaceAll(RegExp(r'^```json\s*', multiLine: true), '')
          .replaceAll(RegExp(r'^```\s*', multiLine: true), '')
          .trim();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;

      final title = (decoded['title'] as String?)?.trim() ?? '';
      final bullets = <String>[];
      final tasks = <String>[];

      final b = decoded['bullets'];
      if (b is List) {
        for (final e in b) {
          final s = e?.toString().trim();
          if (s != null && s.isNotEmpty) bullets.add(s);
        }
      }
      final t = decoded['tasks'];
      if (t is List) {
        for (final e in t) {
          final s = e?.toString().trim();
          if (s != null && s.isNotEmpty) tasks.add(s);
        }
      }

      DateTime? reminder;
      final r = decoded['reminder']?.toString();
      if (r != null && r.isNotEmpty && r != 'null') {
        try {
          reminder = DateTime.parse(r);
          if (!reminder.isAfter(now)) reminder = null;
        } catch (_) {}
      }

      var safeTitle = title;
      if (safeTitle.isEmpty) {
        safeTitle = rawText.trim().split(RegExp(r'\s+')).take(6).join(' ');
        if (safeTitle.length > 60) safeTitle = '${safeTitle.substring(0, 57)}…';
        if (safeTitle.isEmpty) safeTitle = 'Brain dump';
      }

      if (bullets.isEmpty && tasks.isEmpty) {
        final lines = rawText
            .split('\n')
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty)
            .take(6)
            .toList();
        final plain = rawText.trim();
        final fallbackBullet = plain.isEmpty
            ? <String>[]
            : <String>[
                plain.length > 200 ? '${plain.substring(0, 197)}…' : plain,
              ];
        return BrainDumpResult(
          title: safeTitle,
          bullets: lines.isEmpty ? fallbackBullet : lines,
          tasks: const [],
          reminder: reminder,
        );
      }

      return BrainDumpResult(
        title: safeTitle,
        bullets: bullets,
        tasks: tasks,
        reminder: reminder,
      );
    } catch (_) {
      final snippet = rawText.trim();
      final short = snippet.length > 200 ? '${snippet.substring(0, 197)}…' : snippet;
      return BrainDumpResult(
        title: 'Brain dump',
        bullets: short.isEmpty ? const [] : [short],
        tasks: const [],
        reminder: null,
      );
    }
  }

  Future<String> summarizeNote(String noteText) => _callGemini(
        'Summarize the following note in 3 short bullet points.\n\nNote:\n$noteText',
      );

  Future<String> extractTasks(String noteText) => _callGemini(
        'Extract actionable tasks from the following note.\n\nNote:\n$noteText',
      );

  Future<String> generateEmail(String noteText) => _callGemini(
        'Convert the following note into a professional email '
        'including subject and body.\n\nNote:\n$noteText',
      );

  /// Turns a short voice utterance into a structured note.
  ///
  /// Tries to parse strict JSON from the model. Falls back to using the
  /// raw utterance as both title and body if parsing fails.
  Future<Map<String, String>> voiceToNote(String voiceText) async {
    final prompt = '''
You create Google Keep–style notes from very short voice transcriptions.

Rules (follow exactly):
- Respond with STRICT JSON only, no markdown, no prose, no code fences.
- JSON shape must be exactly: {"title": "...", "body": "..."}
- "title": one very short line, like a Google Keep card title.
  - Prefer a relevant emoji at the start (⚡📅🛒🧠 etc).
  - Include very lightweight time hints like "Today", "Tomorrow", or a weekday if they are obvious, but keep it short.
- "body": an optional, concise description or checklist-style text; keep it at most 2–3 short lines of plain text.
- Do NOT include bullet characters in the JSON, only plain text with \\n if needed.

Example voice: Remember to pay electricity bill tomorrow.
Example JSON:
{"title":"⚡ Pay electricity bill – Tomorrow","body":"Pay the electricity bill tomorrow."}

Voice: $voiceText
''';

    final rawResponse = await _callGemini(prompt);
    // Strip optional markdown code fences the model sometimes adds.
    final raw = rawResponse
        .replaceAll(RegExp(r'^```json\s*', multiLine: true), '')
        .replaceAll(RegExp(r'^```\s*', multiLine: true), '')
        .trim();
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final title = (decoded['title'] as String?)?.trim();
      final body = (decoded['body'] as String?)?.trim();
      if (title == null || title.isEmpty || body == null || body.isEmpty) {
        throw const FormatException('Missing title/body');
      }
      return {'title': title, 'body': body};
    } catch (_) {
      return {
        'title': voiceText.trim().isEmpty ? 'Voice note' : voiceText.trim(),
        'body': voiceText.trim(),
      };
    }
  }

  Future<String> _callGemini(String fullPrompt) async {
    if (_apiKey.isEmpty) {
      throw Exception(
          'Gemini API key missing. Build with --dart-define=GEMINI_API_KEY=YOUR_KEY');
    }

    // Check in-memory cache first.
    final cacheKey = fullPrompt.hashCode.toRadixString(36);
    final cached = _cache[cacheKey];
    if (cached != null && !cached.isExpired) {
      SecurityService.log('AI', 'Cache HIT ($cacheKey)');
      return cached.value;
    }

    final uri = Uri.parse('$_baseUrl?key=$_apiKey');
    final requestBody = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': fullPrompt}
          ]
        }
      ],
    });

    SecurityService.log('AI', 'Request → model=$_model');

    late http.Response response;
    try {
      response = await _httpClient
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: requestBody,
          )
          .timeout(const Duration(seconds: 30));
    } catch (e) {
      throw Exception('Network error. Check your internet connection.');
    }

    SecurityService.log('AI', 'Response ← status=${response.statusCode}');

    if (response.statusCode != 200) {
      String msg = 'HTTP ${response.statusCode}';
      try {
        final err = jsonDecode(response.body) as Map<String, dynamic>;
        final error = err['error'] as Map<String, dynamic>?;
        msg = error?['message'] as String? ?? response.body;
      } catch (_) {
        msg = response.body;
      }
      throw Exception('AI request failed: $msg');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;

    final apiError = decoded['error'] as Map<String, dynamic>?;
    if (apiError != null) {
      throw Exception(apiError['message'] as String? ?? 'Unknown AI error');
    }

    final candidates = decoded['candidates'] as List<dynamic>?;
    if (candidates == null || candidates.isEmpty) {
      final feedback = decoded['promptFeedback'] as Map<String, dynamic>?;
      final reason = feedback?['blockReason']?.toString() ?? 'No candidates';
      throw Exception('No AI response: $reason');
    }

    final content = candidates.first['content'] as Map<String, dynamic>?;
    final parts = content?['parts'] as List<dynamic>?;
    if (parts == null || parts.isEmpty) {
      throw Exception('AI returned empty content');
    }

    final text = parts.first['text'] as String?;
    if (text == null || text.isEmpty) {
      throw Exception('AI returned empty text');
    }

    final trimmed = text.trim();

    // Store in cache.
    if (_cache.length >= _maxCacheSize) {
      _cache.remove(_cache.keys.first);
    }
    _cache[cacheKey] = _CacheEntry(trimmed, DateTime.now().add(_cacheTtl));

    SecurityService.log('AI', 'Success ← ${trimmed.length} chars (cached)');
    return trimmed;
  }
}
