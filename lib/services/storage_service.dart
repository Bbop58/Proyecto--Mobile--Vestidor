import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Servicio de almacenamiento seguro para tokens JWT con cache en memoria
class StorageService {
  static const _accessTokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';

  final FlutterSecureStorage _storage;
  final Map<String, String> _memoryCache = {};

  StorageService()
      : _storage = const FlutterSecureStorage(
          aOptions: AndroidOptions(),
          webOptions: WebOptions(
            dbName: 'si2_auth_app',
            publicKey: 'si2_auth_app_key',
          ),
        );

  // Access Token
  Future<String?> getAccessToken() async {
    if (_memoryCache.containsKey(_accessTokenKey)) {
      return _memoryCache[_accessTokenKey];
    }
    try {
      final token = await _storage.read(key: _accessTokenKey).timeout(
            const Duration(seconds: 1),
            onTimeout: () => null,
          );
      if (token != null && token.isNotEmpty) {
        _memoryCache[_accessTokenKey] = token;
        return token;
      }
    } catch (e) {
      debugPrint('Error leyendo access token: $e');
    }
    return null;
  }

  Future<void> setAccessToken(String token) async {
    _memoryCache[_accessTokenKey] = token;
    try {
      await _storage
          .write(key: _accessTokenKey, value: token)
          .timeout(const Duration(seconds: 1));
    } catch (e) {
      debugPrint('Error guardando access token en storage seguro: $e');
    }
  }

  Future<void> deleteAccessToken() async {
    _memoryCache.remove(_accessTokenKey);
    try {
      await _storage
          .delete(key: _accessTokenKey)
          .timeout(const Duration(seconds: 1));
    } catch (e) {
      debugPrint('Error borrando access token: $e');
    }
  }

  // Refresh Token
  Future<String?> getRefreshToken() async {
    if (_memoryCache.containsKey(_refreshTokenKey)) {
      return _memoryCache[_refreshTokenKey];
    }
    try {
      final token = await _storage.read(key: _refreshTokenKey).timeout(
            const Duration(seconds: 1),
            onTimeout: () => null,
          );
      if (token != null && token.isNotEmpty) {
        _memoryCache[_refreshTokenKey] = token;
        return token;
      }
    } catch (e) {
      debugPrint('Error leyendo refresh token: $e');
    }
    return null;
  }

  Future<void> setRefreshToken(String token) async {
    _memoryCache[_refreshTokenKey] = token;
    try {
      await _storage
          .write(key: _refreshTokenKey, value: token)
          .timeout(const Duration(seconds: 1));
    } catch (e) {
      debugPrint('Error guardando refresh token: $e');
    }
  }

  Future<void> deleteRefreshToken() async {
    _memoryCache.remove(_refreshTokenKey);
    try {
      await _storage
          .delete(key: _refreshTokenKey)
          .timeout(const Duration(seconds: 1));
    } catch (e) {
      debugPrint('Error borrando refresh token: $e');
    }
  }

  // Limpiar todo
  Future<void> clearAll() async {
    _memoryCache.clear();
    try {
      await _storage.deleteAll().timeout(const Duration(seconds: 1));
    } catch (e) {
      debugPrint('Error limpiando storage: $e');
    }
  }

  // Verificar si hay token guardado
  Future<bool> hasToken() async {
    final token = await getAccessToken();
    return token != null && token.isNotEmpty;
  }
}



