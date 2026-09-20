import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'storage_service.dart';
import '../config/api_config.dart';

/// Cliente HTTP base con inyección automática de JWT
class ApiService {
  final StorageService _storageService;
  final http.Client _client;

  ApiService(this._storageService) : _client = http.Client();

  /// Headers base con Content-Type JSON
  Map<String, String> get _baseHeaders => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  /// Headers con token de autorización
  Future<Map<String, String>> _authHeaders() async {
    final token = await _storageService.getAccessToken();
    final headers = Map<String, String>.from(_baseHeaders);
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  /// POST request (sin auth)
  Future<ApiResponse> post(String url, Map<String, dynamic> body) async {
    try {
      final response = await _client
          .post(
            Uri.parse(url),
            headers: _baseHeaders,
            body: jsonEncode(body),
          )
          .timeout(ApiConfig.connectionTimeout);
      return _handleResponse(response);
    } on SocketException {
      return ApiResponse(
        success: false,
        statusCode: 0,
        error: 'Sin conexión a internet. Verifica tu red.',
      );
    } catch (e) {
      return ApiResponse(
        success: false,
        statusCode: 0,
        error: 'Error de conexión: ${e.toString()}',
      );
    }
  }

  /// POST request (con auth)
  Future<ApiResponse> postAuth(String url,
      [Map<String, dynamic>? body, Duration? timeout]) async {
    try {
      final headers = await _authHeaders();
      final response = await _client
          .post(
            Uri.parse(url),
            headers: headers,
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(timeout ?? ApiConfig.connectionTimeout);
      return _handleResponse(response);
    } on SocketException {
      return ApiResponse(
        success: false,
        statusCode: 0,
        error: 'Sin conexión a internet. Verifica tu red.',
      );
    } catch (e) {
      return ApiResponse(
        success: false,
        statusCode: 0,
        error: 'Error de conexión: ${e.toString()}',
      );
    }
  }

  /// POST form-urlencoded (para login OAuth2)
  Future<ApiResponse> postForm(
      String url, Map<String, String> body) async {
    try {
      final response = await _client
          .post(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/x-www-form-urlencoded',
              'Accept': 'application/json',
            },
            body: body,
          )
          .timeout(ApiConfig.connectionTimeout);
      return _handleResponse(response);
    } on SocketException {
      return ApiResponse(
        success: false,
        statusCode: 0,
        error: 'Sin conexión a internet. Verifica tu red.',
      );
    } catch (e) {
      return ApiResponse(
        success: false,
        statusCode: 0,
        error: 'Error de conexión: ${e.toString()}',
      );
    }
  }

  /// GET request (con auth)
  Future<ApiResponse> getAuth(String url) async {
    try {
      final headers = await _authHeaders();
      final response = await _client
          .get(Uri.parse(url), headers: headers)
          .timeout(ApiConfig.connectionTimeout);
      return _handleResponse(response);
    } on SocketException {
      return ApiResponse(
        success: false,
        statusCode: 0,
        error: 'Sin conexión a internet. Verifica tu red.',
      );
    } catch (e) {
      return ApiResponse(
        success: false,
        statusCode: 0,
        error: 'Error de conexión: ${e.toString()}',
      );
    }
  }

  /// PUT request (con auth)
  Future<ApiResponse> putAuth(
      String url, Map<String, dynamic> body) async {
    try {
      final headers = await _authHeaders();
      final response = await _client
          .put(
            Uri.parse(url),
            headers: headers,
            body: jsonEncode(body),
          )
          .timeout(ApiConfig.connectionTimeout);
      return _handleResponse(response);
    } on SocketException {
      return ApiResponse(
        success: false,
        statusCode: 0,
        error: 'Sin conexión a internet. Verifica tu red.',
      );
    } catch (e) {
      return ApiResponse(
        success: false,
        statusCode: 0,
        error: 'Error de conexión: ${e.toString()}',
      );
    }
  }

  /// PATCH request (con auth)
  Future<ApiResponse> patchAuth(
      String url, [Map<String, dynamic>? body]) async {
    try {
      final headers = await _authHeaders();
      final response = await _client
          .patch(
            Uri.parse(url),
            headers: headers,
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(ApiConfig.connectionTimeout);
      return _handleResponse(response);
    } on SocketException {
      return ApiResponse(
        success: false,
        statusCode: 0,
        error: 'Sin conexión a internet. Verifica tu red.',
      );
    } catch (e) {
      return ApiResponse(
        success: false,
        statusCode: 0,
        error: 'Error de conexión: ${e.toString()}',
      );
    }
  }

  /// Manejo centralizado de respuestas
  ApiResponse _handleResponse(http.Response response) {
    final statusCode = response.statusCode;
    dynamic data;

    try {
      data = jsonDecode(response.body);
    } catch (_) {
      data = response.body;
    }

    if (statusCode >= 200 && statusCode < 300) {
      return ApiResponse(
        success: true,
        statusCode: statusCode,
        data: data,
      );
    }

    // Extraer mensaje de error del backend
    String errorMessage;
    if (data is Map<String, dynamic>) {
      errorMessage = data['detail']?.toString() ??
          data['message']?.toString() ??
          'Error desconocido';
    } else {
      errorMessage = 'Error del servidor ($statusCode)';
    }

    return ApiResponse(
      success: false,
      statusCode: statusCode,
      error: errorMessage,
      data: data,
    );
  }

  void dispose() {
    _client.close();
  }
}

/// Wrapper de respuesta API
class ApiResponse {
  final bool success;
  final int statusCode;
  final dynamic data;
  final String? error;
  final String? message;

  ApiResponse({
    required this.success,
    required this.statusCode,
    this.data,
    this.error,
    this.message,
  });
}
