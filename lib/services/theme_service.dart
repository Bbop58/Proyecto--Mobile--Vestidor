import 'package:flutter/material.dart';
import 'storage_service.dart';
import '../models/tenant_model.dart';

/// Servicio de gestión de tema (Light / Dark mode) y Tenant Brand Morphing
class ThemeService extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.light;
  TenantModel? _selectedTenant;

  ThemeService([StorageService? storage]);

  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;
  TenantModel? get selectedTenant => _selectedTenant;
  Color? get tenantAccent => _selectedTenant?.parsedPrimaryColor;

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

  void setSelectedTenant(TenantModel? tenant) {
    _selectedTenant = tenant;
    notifyListeners();
  }
}
