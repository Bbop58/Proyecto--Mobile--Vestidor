import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'dart:convert';

import '../models/mobile_session.dart';

/// Servicio de almacenamiento seguro para tokens JWT con cache en memoria
class StorageService {
  static const _accessTokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';
  static const _userIdKey = 'user_id';

  final FlutterSecureStorage _storage;
  final Map<String, String> _memoryCache = {};
  static const sessionEnvelopeKey = 'mobile_session_v1';
  Future<void> _sessionQueue = Future.value();
  SessionEnvelope? _sessionEnvelope;
  bool _sessionRead = false;
  final Duration _sessionTimeout;

  Future<T> _sessionOperation<T>(Future<T> Function() action) {
    final operation = _sessionQueue.then((_) => action());
    // A UI deadline must not release a still-running native write. A later
    // logout stays behind it and wins durably instead of racing the plugin.
    _sessionQueue = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation.timeout(
      _sessionTimeout,
      onTimeout: () => throw const SessionStorageException(),
    );
  }

  Future<SessionEnvelope?> readSessionEnvelope() => _sessionOperation(() async {
    try {
      if (_sessionRead) return _sessionEnvelope;
      final raw = await _storage.read(key: sessionEnvelopeKey);
      final value = raw == null
          ? null
          : SessionEnvelope.fromJson(
              Map<String, dynamic>.from(jsonDecode(raw) as Map),
            );
      _sessionEnvelope = value;
      _sessionRead = true;
      return value;
    } catch (_) {
      throw const SessionStorageException();
    }
  });

  Future<void> writeSessionEnvelope(SessionEnvelope value) =>
      _sessionOperation(() async {
        try {
          await _storage.write(
            key: sessionEnvelopeKey,
            value: jsonEncode(value.toJson()),
          );
          _sessionEnvelope = value;
          _sessionRead = true;
        } catch (_) {
          throw const SessionStorageException();
        }
      });

  Future<Map<String, String>?> readLegacySession() =>
      _sessionOperation(() async {
        try {
          final access = await _storage.read(key: _accessTokenKey);
          final refresh = await _storage.read(key: _refreshTokenKey);
          if ((access == null || access.isEmpty) &&
              (refresh == null || refresh.isEmpty)) {
            return null;
          }
          return {
            if (access != null && access.isNotEmpty) 'access_token': access,
            if (refresh != null && refresh.isNotEmpty) 'refresh_token': refresh,
          };
        } catch (_) {
          throw const SessionStorageException();
        }
      });

  Future<void> clearLegacySession() => _sessionOperation(() async {
    try {
      for (final key in [_accessTokenKey, _refreshTokenKey, _userIdKey]) {
        await _storage.delete(key: key);
        _memoryCache.remove(key);
      }
    } catch (_) {
      throw const SessionStorageException();
    }
  });

  StorageService({Duration sessionTimeout = const Duration(seconds: 8)})
    // Public test injection intentionally differs from the private field.
    // ignore: prefer_initializing_formals
    : _sessionTimeout = sessionTimeout,
      _storage = const FlutterSecureStorage(
        aOptions: AndroidOptions(),
        webOptions: WebOptions(
          dbName: 'si2_auth_app',
          publicKey: 'si2_auth_app_key',
        ),
      );

  // Access Token
  Future<String?> getAccessToken() async {
    if (_sessionRead && _sessionEnvelope != null) {
      return _sessionEnvelope!.active?.accessToken;
    }
    if (_memoryCache.containsKey(_accessTokenKey)) {
      return _memoryCache[_accessTokenKey];
    }
    try {
      final token = await _storage
          .read(key: _accessTokenKey)
          .timeout(const Duration(seconds: 1), onTimeout: () => null);
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
      final token = await _storage
          .read(key: _refreshTokenKey)
          .timeout(const Duration(seconds: 1), onTimeout: () => null);
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

  // User ID
  Future<String?> getUserId() async {
    if (_sessionRead && _sessionEnvelope != null) {
      return _sessionEnvelope!.active?.identity.userId;
    }
    if (_memoryCache.containsKey(_userIdKey)) {
      return _memoryCache[_userIdKey];
    }
    try {
      final uid = await _storage
          .read(key: _userIdKey)
          .timeout(const Duration(seconds: 1), onTimeout: () => null);
      if (uid != null && uid.isNotEmpty) {
        _memoryCache[_userIdKey] = uid;
        return uid;
      }
    } catch (_) {}
    return null;
  }

  Future<void> setUserId(String userId) async {
    _memoryCache[_userIdKey] = userId;
    try {
      await _storage
          .write(key: _userIdKey, value: userId)
          .timeout(const Duration(seconds: 1));
    } catch (_) {}
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
