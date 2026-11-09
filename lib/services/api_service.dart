import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../core/database/database_helper.dart';
import '../config/api_config.dart';
import '../models/mobile_session.dart';
import 'storage_service.dart';
import 'mobile_session_service.dart';

/// HTTP boundary: preserve owner/generation, renew access, never replay money implicitly.
class ApiService {
  final StorageService _storageService;
  final http.Client _client;
  MobileSessionService? _sessions;
  bool _ownsSessions = false;
  // Keep the public injection name separate from the private implementation field.
  ApiService(
    this._storageService, {
    http.Client? client,
    MobileSessionService? sessions,
  }) : _client = client ?? http.Client(),
       // Public injection name intentionally differs from the private field.
       // ignore: prefer_initializing_formals
       _sessions = sessions;
  MobileSessionService get sessions {
    if (_sessions == null) {
      _sessions = MobileSessionService(_storageService, client: _client);
      _ownsSessions = true;
    }
    return _sessions!;
  }

  MobileSessionService? get sessionCoordinator => _sessions;

  /// Queue transport barrier. Connectivity is not proof of a valid session.
  Future<bool> prepareSession({required String expectedScope, bool revalidate = true}) async {
    final coordinator = _sessions;
    final generation = coordinator?.generation;
    if (DatabaseHelper.scope != expectedScope) return false;
    if (coordinator == null) return true; // Legacy clients/test doubles retain their contract.
    try {
      final ready = revalidate ? await coordinator.revalidate()
        : coordinator.hasIdentity && coordinator.state == SessionState.online;
      return ready && DatabaseHelper.scope == expectedScope && generation == coordinator.generation;
    } catch (_) { return false; }
  }

  Future<ApiResponse> _request(
    String method,
    String url, {
    Map<String, dynamic>? body,
    bool authenticated = true,
    bool optional = false,
    Duration? timeout,
    String? expectedScope,
  }) async {
    final scope = expectedScope ?? DatabaseHelper.scope;
    final coordinator = _sessions;
    final generation = coordinator?.generation;
    bool current() =>
        scope == DatabaseHelper.scope &&
        (coordinator == null || generation == coordinator.generation);
    ApiResponse changed() =>
        ApiResponse(success: false, statusCode: 401, error: 'La sesión cambió');
    if (!current()) return changed();
    if (coordinator != null &&
        authenticated &&
        Uri.parse(url).origin != Uri.parse(ApiConfig.baseUrl).origin) {
      return ApiResponse(
        success: false,
        statusCode: 0,
        error: 'No se enviaron credenciales a un servidor diferente.',
      );
    }
    try {
      String? token;
      if (authenticated) {
        token = coordinator != null
            ? await coordinator.accessToken()
            : await _storageService.getAccessToken();
      }
      if (!current()) return changed();
      if (authenticated && !optional && token == null && coordinator != null) {
        return ApiResponse(
          success: false,
          statusCode: 401,
          error: 'Inicia sesión para continuar.',
        );
      }
      Future<http.Response> send(String? access) async {
        final request = http.Request(method, Uri.parse(url))
          ..followRedirects = false;
        request.headers.addAll({
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          if (access != null) 'Authorization': 'Bearer $access',
        });
        if (body != null) request.body = jsonEncode(body);
        return http.Response.fromStream(await _client.send(request));
      }

      var response = await send(token)
          .timeout(timeout ?? ApiConfig.connectionTimeout);
      if (!current()) return changed();
      if (response.statusCode == 401 && coordinator != null && token != null) {
        final renewed = await coordinator.accessToken(
          forceRefresh: true,
          rejectedAccessToken: token,
        );
        if (!current()) return changed();
        if (renewed != null && (method == 'GET' || method == 'HEAD')) {
          response = await send(renewed)
              .timeout(timeout ?? ApiConfig.connectionTimeout);
          if (!current()) return changed();
        } else if (renewed != null) {
          return ApiResponse(
            success: false,
            statusCode: 401,
            error: 'La sesión se renovó. Vuelve a intentar la operación.',
            data: {
              'detail': {'code': 'SESSION_RENEWED_RETRY_REQUIRED'},
            },
          );
        }
      }
      return _handleResponse(response);
    } on SessionFailure catch (error) {
      if (!current()) return changed();
      return ApiResponse(
        success: false,
        statusCode: error.statusCode,
        error: error.message,
        data: {
          'detail': {'code': error.code},
        },
      );
    } on SessionStorageException {
      return ApiResponse(
        success: false,
        statusCode: 0,
        error: const SessionStorageException().toString(),
      );
    } catch (_) {
      return ApiResponse(
        success: false,
        statusCode: 0,
        error: 'No se pudo conectar con el servidor. Reintenta.',
      );
    }
  }

  Future<ApiResponse> get(String url) => _request('GET', url, optional: true);
  Future<ApiResponse> getAuth(String url) => _request('GET', url);
  /// Canonical PDF bytes; same identity/refresh boundary as authenticated JSON GET.
  Future<Uint8List> getAuthPdf(String url,{String? expectedScope}) async {
    final scope=expectedScope??DatabaseHelper.scope,coordinator=_sessions;
    final generation=coordinator?.generation;
    bool current()=>scope!=null && scope==DatabaseHelper.scope &&
      (coordinator==null || generation==coordinator.generation);
    if(!current() || Uri.parse(url).origin!=Uri.parse(ApiConfig.baseUrl).origin){
      throw StateError('La sesión o el servidor cambió.');
    }
    String? token=coordinator!=null?await coordinator.accessToken():await _storageService.getAccessToken();
    Future<http.Response> send(String access) async {
      if(!current())throw StateError('La sesión cambió.');
      final request=http.Request('GET',Uri.parse(url))..followRedirects=false;
      request.headers.addAll({'Authorization':'Bearer $access','Accept':'application/pdf'});
      return http.Response.fromStream(await _client.send(request)).timeout(const Duration(seconds:40));
    }
    if(token==null || !current())throw StateError('Inicia sesión para descargar.');
    var response=await send(token);
    if(!current())throw StateError('La sesión cambió.');
    if(response.statusCode==401 && coordinator!=null){
      token=await coordinator.accessToken(forceRefresh:true,rejectedAccessToken:token);
      if(token==null || !current())throw StateError('Inicia sesión para descargar.');
      response=await send(token);
    }
    if(!current())throw StateError('La sesión cambió.');
    if(response.statusCode!=200 || !(response.headers['content-type']??'').startsWith('application/pdf') ||
      response.bodyBytes.length<5 || ascii.decode(response.bodyBytes.take(5).toList(),allowInvalid:true)!='%PDF-'){
      throw StateError('No se pudo descargar el comprobante. Revisa tu conexión y permisos.');
    }
    return response.bodyBytes;
  }
  Future<ApiResponse> post(String url, Map<String, dynamic> body) =>
      _request('POST', url, body: body, authenticated: false);
  Future<ApiResponse> postAuth(
    String url, [
    Map<String, dynamic>? body,
    Duration? timeout,
    String? expectedScope,
  ]) => _request(
    'POST',
    url,
    body: body,
    timeout: timeout,
    expectedScope: expectedScope,
  );
  Future<ApiResponse> putAuth(String url, Map<String, dynamic> body) =>
      _request('PUT', url, body: body);
  Future<ApiResponse> deleteAuth(String url) => _request('DELETE', url);
  Future<ApiResponse> patchAuth(String url, [Map<String, dynamic>? body]) =>
      _request('PATCH', url, body: body);
  Future<ApiResponse> postForm(String url, Map<String, String> body) async {
    try {
      final request = http.Request('POST', Uri.parse(url))
        ..followRedirects = false;
      request.bodyFields = body;
      final response = await http.Response.fromStream(
        await _client.send(request),
      ).timeout(ApiConfig.connectionTimeout);
      return _handleResponse(response);
    } catch (_) {
      return ApiResponse(
        success: false,
        statusCode: 0,
        error: 'No se pudo conectar con el servidor.',
      );
    }
  }

  ApiResponse _handleResponse(http.Response response) {
    dynamic data;
    try {
      data = jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      data = null;
    }
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return ApiResponse(
        success: true,
        statusCode: response.statusCode,
        data: data,
      );
    }
    final detail = data is Map ? data['detail'] : null;
    return ApiResponse(
      success: false,
      statusCode: response.statusCode,
      data: data,
      error: detail is String
          ? detail
          : detail is Map && detail['message'] is String
          ? detail['message'] as String
          : 'Error del servidor (${response.statusCode})',
    );
  }

  void dispose() {
    if (_ownsSessions) _sessions?.dispose();
    _client.close();
  }
}

class ApiResponse {
  final bool success;
  final int statusCode;
  final dynamic data;
  final String? error, message;
  ApiResponse({
    required this.success,
    required this.statusCode,
    this.data,
    this.error,
    this.message,
  });
}
