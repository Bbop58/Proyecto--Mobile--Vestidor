import 'package:flutter/foundation.dart';

/// Configuración de la API
class ApiConfig {
  // En Web o Windows Desktop usa 127.0.0.1 (IPv4), en Android emulador usa 10.0.2.2
  static String get baseUrl {
    if (kIsWeb) return 'http://127.0.0.1:8000';
    return defaultTargetPlatform == TargetPlatform.android
        ? 'http://10.0.2.2:8000'
        : 'http://127.0.0.1:8000';
  }

  static const String apiVersion = '/api/v1';
  static String get apiUrl => '$baseUrl$apiVersion';

  // Auth endpoints
  static String get loginUrl => '$apiUrl/auth/login';
  static String get registerUrl => '$apiUrl/auth/register';
  static String get logoutUrl => '$apiUrl/auth/logout';

  // User endpoints
  static String get profileUrl => '$apiUrl/users/me';

  // Timeouts
  static const Duration connectionTimeout = Duration(seconds: 8);
  static const Duration receiveTimeout = Duration(seconds: 8);
}

