import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// User-controlled theme mode (system / dark / light), persisted in Hive.
class ThemeNotifier extends ChangeNotifier {
  static const _boxName = 'app_settings';
  static const _key = 'theme_mode';

  ThemeMode _mode = ThemeMode.system;
  ThemeMode get mode => _mode;

  Future<void> init() async {
    final box = await Hive.openBox(_boxName);
    final saved = box.get(_key) as String?;
    if (saved == 'light') {
      _mode = ThemeMode.light;
    } else if (saved == 'dark') {
      _mode = ThemeMode.dark;
    } else {
      _mode = ThemeMode.system;
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    _mode = mode;
    notifyListeners();
    final box = await Hive.openBox(_boxName);
    await box.put(_key, mode.name);
  }

  /// Cycles: system → dark → light → system
  void cycle() {
    switch (_mode) {
      case ThemeMode.system:
        setMode(ThemeMode.dark);
      case ThemeMode.dark:
        setMode(ThemeMode.light);
      case ThemeMode.light:
        setMode(ThemeMode.system);
    }
  }

  IconData get icon {
    switch (_mode) {
      case ThemeMode.system:
        return Icons.brightness_auto;
      case ThemeMode.dark:
        return Icons.dark_mode;
      case ThemeMode.light:
        return Icons.light_mode;
    }
  }

  String get label {
    switch (_mode) {
      case ThemeMode.system:
        return 'System';
      case ThemeMode.dark:
        return 'Dark';
      case ThemeMode.light:
        return 'Light';
    }
  }
}
