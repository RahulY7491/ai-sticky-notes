import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import 'models/note.dart';
import 'screens/ask_notes_screen.dart';
import 'screens/home_screen.dart';
import 'screens/memory_timeline_screen.dart';
import 'screens/note_editor_screen.dart';
import 'features/brain_dump/presentation/brain_dump_screen.dart';
import 'services/reminder_service.dart';
import 'services/theme_notifier.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Hive.initFlutter();

    final themeNotifier = ThemeNotifier();
    await themeNotifier.init();
    await ReminderService.instance.init();

    runApp(AIStickyNotesApp(themeNotifier: themeNotifier));
  } catch (e, st) {
    runApp(ErrorApp(error: e.toString(), stack: st.toString()));
  }
}

class ErrorApp extends StatelessWidget {
  final String error;
  final String stack;

  const ErrorApp({super.key, required this.error, required this.stack});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Could not start app',
                    style: TextStyle(fontSize: 20)),
                const SizedBox(height: 8),
                Expanded(
                    child: SingleChildScrollView(child: Text(error))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AIStickyNotesApp extends StatelessWidget {
  final ThemeNotifier themeNotifier;

  const AIStickyNotesApp({super.key, required this.themeNotifier});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => NotesProvider()),
        ChangeNotifierProvider.value(value: themeNotifier),
      ],
      child: Consumer<ThemeNotifier>(
        builder: (context, theme, _) {
          return MaterialApp(
            title: 'AI Sticky Notes',
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFF6750A4),
                brightness: Brightness.light,
              ),
              useMaterial3: true,
              appBarTheme: const AppBarTheme(
                centerTitle: true,
                elevation: 0,
              ),
              cardTheme: CardThemeData(
                elevation: 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              elevatedButtonTheme: ElevatedButtonThemeData(
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              snackBarTheme: const SnackBarThemeData(
                behavior: SnackBarBehavior.floating,
              ),
            ),
            darkTheme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFF6750A4),
                brightness: Brightness.dark,
              ),
              useMaterial3: true,
              appBarTheme:
                  const AppBarTheme(centerTitle: true, elevation: 0),
              cardTheme: CardThemeData(
                elevation: 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              snackBarTheme: const SnackBarThemeData(
                behavior: SnackBarBehavior.floating,
              ),
            ),
            themeMode: theme.mode,
            routes: {
              '/': (context) => const HomeScreen(),
              '/edit': (context) {
                final args =
                    ModalRoute.of(context)?.settings.arguments;
                return NoteEditorScreen(
                    note: args is Note ? args : null);
              },
              '/timeline': (context) => const MemoryTimelineScreen(),
              '/ask': (context) => const AskNotesScreen(),
              '/brain-dump': (context) => const BrainDumpScreen(),
            },
          );
        },
      ),
    );
  }
}
