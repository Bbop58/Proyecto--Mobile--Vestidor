import 'package:flutter/foundation.dart';

class ApiConfig {
  // Para Producción: puedes cambiar esta URL por la de Railway,
  // o compilar con: flutter build apk --release --dart-define=API_URL=https://tu-backend.up.railway.app
  static const String _envUrl = String.fromEnvironment('API_URL', defaultValue: '');

  // URL de producción por defecto si no se pasa por --dart-define (dejar vacía para modo local automático)
  static const String productionUrl = '';

  static String get baseUrl {
    if (_envUrl.isNotEmpty) return _envUrl;
    if (productionUrl.isNotEmpty) return productionUrl;

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

  // PayPal Endpoints
  static String get paypalConfigUrl => '$apiUrl/payments/paypal/config';
  static String get paypalCreateOrderUrl => '$apiUrl/payments/paypal/create-order';
  static String get paypalCaptureOrderUrl => '$apiUrl/payments/paypal/capture-order';

  // Timeouts
  static const Duration connectionTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 10);
}

