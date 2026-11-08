import 'dart:async';

import 'package:flutter/foundation.dart';

import '../config/api_config.dart';
import '../core/database/database_helper.dart';
import '../models/user.dart';
import '../models/mobile_session.dart';
import 'api_service.dart';
import 'storage_service.dart';
import 'mobile_session_service.dart';

/// UI adapter for the single durable session coordinator.
class AuthService extends ChangeNotifier {
  final ApiService _apiService;
  late final MobileSessionService _sessions;
  User? _currentUser;
  bool _isLoading = false, _platformOnly = false;
  int _authEpoch = 0;
  String? _error;
  AuthService(this._apiService, StorageService storage) {
    _sessions = _apiService.sessions;
    _sessions.addListener(_syncSession);
    _syncSession(notify: false);
  }
  User? get currentUser => _currentUser;
  bool get isAuthenticated =>
      _sessions.hasIdentity && _currentUser?.canUseMobile == true;
  SessionState get sessionState => _sessions.state;
  Future<void> revalidateSession() async { await _sessions.revalidate(); }
  bool get isLoading => _isLoading || _sessions.state == SessionState.restoring;
  String? get error => _error ?? _sessions.notice;
  bool get platformOnly => _platformOnly || _sessions.platformDenied;
  bool get sessionRecoveryNeeded =>
      _sessions.state == SessionState.storageError ||
      _sessions.awaitingLegacyConnection;
  String get sessionRecoveryMessage =>
      _sessions.notice ?? 'Conéctate para recuperar tu sesión anterior.';
  void dismissPlatformAccess() {
    _platformOnly = false;
    _sessions.dismissPlatformAccess();
    _error = null;
    notifyListeners();
  }

  void _syncSession({bool notify = true}) {
    final raw = _sessions.profile;
    _currentUser = raw == null ? null : User.fromJson(raw);
    DatabaseHelper.activateScope(
      isAuthenticated ? _sessions.identity?.scope : null,
    );
    if (notify) notifyListeners();
  }

  Future<void> initialize() async {
    if (_isLoading) return;
    final epoch = _authEpoch;
    _setLoading(true);
    try {
      await _sessions.restore();
    } finally {
      if (epoch == _authEpoch) _setLoading(false);
    }
  }

  Future<void> retrySession() async {
    final epoch = _authEpoch;
    _setLoading(true);
    _error = null;
    try {
      if (_sessions.logoutNeedsRetry) {
        await _sessions.signOut();
      } else {
        await _sessions.restore(retry: true);
      }
    } on SessionStorageException {
      _error = const SessionStorageException().toString();
    } finally {
      if (epoch == _authEpoch) _setLoading(false);
    }
  }

  Future<bool> _establishLegacy(
    dynamic raw,
    int epoch,
    int sessionAttempt,
  ) async {
    if (epoch != _authEpoch) return false;
    if (raw is! Map<String, dynamic> || raw['access_token'] is! String) {
      _setError('El servidor no devolvió una sesión válida.');
      return false;
    }
    final profile = raw['user'];
    if (profile is Map<String, dynamic> &&
        !User.fromJson(profile).canUseMobile) {
      await _sessions.signOut();
      _platformOnly = true;
      _setError(
        'Esta cuenta se gestiona en la web de FashionStore. El panel de plataforma no está disponible en la app móvil.',
      );
      return false;
    }
    await _sessions.bootstrap(
      legacyAccessToken: raw['access_token'] as String,
      legacyRefreshToken: raw['refresh_token'] as String?,
      attempt: sessionAttempt,
    );
    if (epoch != _authEpoch) return false;
    unawaited(_sessions.flushPendingRevocations());
    return isAuthenticated;
  }

  Future<bool> login({required String email, required String password}) async {
    if (isLoading) return false;
    final epoch = ++_authEpoch;
    int? attempt;
    _setLoading(true);
    _error = null;
    _platformOnly = false;
    try {
      attempt = _sessions.beginAuthentication();
      final response = await _apiService.post(ApiConfig.loginUrl, {
        'email': email,
        'password': password,
      });
      if (epoch != _authEpoch) return false;
      if (!response.success) {
        _sessions.cancelAuthentication(attempt);
        _setError(response.error ?? 'No se pudo iniciar sesión.');
        return false;
      }
      return await _establishLegacy(response.data, epoch, attempt);
    } on SessionStorageException {
      if (epoch == _authEpoch) {
        _setError(const SessionStorageException().toString());
      }
      return false;
    } on SessionFailure catch (e) {
      if (epoch == _authEpoch) {
        if (attempt != null) _sessions.cancelAuthentication(attempt);
        _setError(e.message);
      }
      return false;
    } catch (_) {
      if (epoch == _authEpoch) {
        if (attempt != null) _sessions.cancelAuthentication(attempt);
        _setError('No se pudo iniciar sesión. Reintenta.');
      }
      return false;
    } finally {
      if (epoch == _authEpoch) _setLoading(false);
    }
  }

  Future<bool> register({
    required String email,
    required String password,
    required String fullName,
    required String tenantId,
  }) async {
    if (isLoading) return false;
    final epoch = ++_authEpoch;
    int? attempt;
    var accountCreated = false;
    _setLoading(true);
    _error = null;
    try {
      attempt = _sessions.beginAuthentication();
      final response = await _apiService.post(ApiConfig.registerUrl, {
        'email': email,
        'password': password,
        'full_name': fullName,
        'tenant_id': tenantId,
      });
      if (epoch != _authEpoch) return false;
      if (!response.success) {
        _sessions.cancelAuthentication(attempt);
        _setError(response.error ?? 'No se pudo registrar la cuenta.');
        return false;
      }
      accountCreated = true;
      var raw = response.data;
      if (raw is! Map<String, dynamic> || raw['access_token'] is! String) {
        final login = await _apiService.post(ApiConfig.loginUrl, {
          'email': email,
          'password': password,
        });
        if (epoch != _authEpoch) return false;
        if (!login.success) {
          throw const SessionFailure(
            0,
            'REGISTERED',
            'Cuenta creada. Vuelve a iniciar sesión.',
          );
        }
        raw = login.data;
      }
      return await _establishLegacy(raw, epoch, attempt);
    } catch (_) {
      if (epoch == _authEpoch) {
        if (attempt != null && _sessions.state != SessionState.storageError) {
          _sessions.cancelAuthentication(attempt);
        }
        _setError(
          accountCreated
              ? 'Cuenta creada. No se pudo guardar la sesión; vuelve a iniciar sesión.'
              : 'No se pudo completar el registro. Reintenta.',
        );
      }
      return false;
    } finally {
      if (epoch == _authEpoch) _setLoading(false);
    }
  }

  Future<bool> logout() async {
    final epoch = ++_authEpoch;
    _setLoading(true);
    _error = null;
    try {
      await _sessions.signOut();
      return true;
    } on SessionStorageException {
      _setError(
        'No se pudo guardar el cierre de sesión. Reintenta antes de cerrar la app.',
      );
      return false;
    } finally {
      if (epoch == _authEpoch) _setLoading(false);
    }
  }

  Future<bool> updateProfile({String? fullName, String? email}) async {
    final generation = _sessions.generation;
    _setLoading(true);
    _error = null;
    try {
      final response = await _apiService.putAuth(ApiConfig.profileUrl, {
        if (fullName != null) 'full_name': fullName,
        if (email != null) 'email': email,
      });
      if (generation != _sessions.generation) return false;
      if (response.success && response.data is Map<String, dynamic>) {
        await _sessions.updateProfile(response.data as Map<String, dynamic>);
        return generation == _sessions.generation;
      }
      _setError(response.error ?? 'No se pudo actualizar el perfil.');
      return false;
    } catch (_) {
      if (generation == _sessions.generation) {
        _setError('No se pudo guardar el perfil. Reintenta.');
      }
      return false;
    } finally {
      if (generation == _sessions.generation) _setLoading(false);
    }
  }

  Future<Map<String, dynamic>> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final generation = _sessions.generation;
    _setLoading(true);
    _error = null;
    try {
      final response = await _apiService.postAuth(ApiConfig.changePasswordUrl, {
        'current_password': currentPassword,
        'new_password': newPassword,
      });
      if (generation != _sessions.generation) {
        return {'success': false, 'message': 'La sesión cambió.'};
      }
      if (response.success) {
        await logout();
        return {
          'success': true,
          'message': 'Contraseña actualizada. Vuelve a iniciar sesión.',
        };
      }
      final message = response.error ?? 'No se pudo cambiar la contraseña.';
      _setError(message);
      return {'success': false, 'message': message};
    } catch (_) {
      return {
        'success': false,
        'message': 'No se pudo completar el cambio. Reintenta.',
      };
    } finally {
      if (generation == _sessions.generation) _setLoading(false);
    }
  }

  Future<List<Map<String, dynamic>>> getRegistrationCompanies() async {
    final response = await _apiService.get(ApiConfig.publicTenantsUrl);
    if (!response.success || response.data is! List) {
      throw StateError('No se pudieron cargar las empresas');
    }
    return (response.data as List)
        .map((v) => Map<String, dynamic>.from(v as Map))
        .toList();
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void _setError(String message) {
    _error = message;
    notifyListeners();
  }

  @override
  void dispose() {
    _sessions.removeListener(_syncSession);
    super.dispose();
  }
}
