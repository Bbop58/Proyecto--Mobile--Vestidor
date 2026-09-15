import 'package:flutter/material.dart';
import 'storage_service.dart';

/// Servicio de gestión de tema (Light / Dark mode) con persistencia
class ThemeService extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.light;

  ThemeService([StorageService? storage]);

  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;

  void toggleTheme() {
    if (_themeMode == ThemeMode.light) {
      _themeMode = ThemeMode.dark;
    } else {
      _themeMode = ThemeMode.light;
    }
    notifyListeners();
  }

  void setThemeMode(ThemeMode mode) {
    if (_themeMode != mode) {
      _themeMode = mode;
      notifyListeners();
    }
  }
}
