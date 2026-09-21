import 'package:flutter/foundation.dart';
import '../config/api_config.dart';
import '../models/user.dart';
import 'api_service.dart';
import 'storage_service.dart';

/// Servicio de autenticación — gestiona login, register, logout y estado del usuario
class AuthService extends ChangeNotifier {
  final ApiService _apiService;
  final StorageService _storageService;

  User? _currentUser;
  bool _isLoading = false;
  bool _isAuthenticated = false;
  String? _error;

  AuthService(this._apiService, this._storageService);

  // Getters
  User? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _isAuthenticated;
  String? get error => _error;

  bool _isInitializing = false;

  /// Inicializar — verificar si hay sesión guardada
  Future<void> initialize() async {
    if (_isInitializing) return;
    _isInitializing = true;
    _isLoading = true;
    notifyListeners();

    try {
      final hasToken = await _storageService.hasToken().timeout(
            const Duration(seconds: 2),
            onTimeout: () => false,
          );

      if (hasToken) {
        await _loadProfile().timeout(
          const Duration(seconds: 3),
          onTimeout: () {
            debugPrint('Timeout al verificar token/perfil en servidor');
          },
        );
      }
    } catch (e) {
      debugPrint('Error initializing auth: $e');
      await _storageService.clearAll();
    } finally {
      _isLoading = false;
      _isInitializing = false;
      notifyListeners();
    }
  }


  /// Registrar nuevo usuario
  Future<bool> register({
    required String email,
    required String password,
    required String fullName,
  }) async {
    _setLoading(true);
    _clearError();

    try {
      final response = await _apiService.post(
        ApiConfig.registerUrl,
        {
          'email': email,
          'password': password,
          'full_name': fullName,
        },
      );

      if (response.success && response.data != null) {
        final data = response.data;
        if (data is Map<String, dynamic> && data.containsKey('access_token')) {
          final accessToken = data['access_token'] as String;
          await _storageService.setAccessToken(accessToken);

          if (data['refresh_token'] != null) {
            await _storageService.setRefreshToken(data['refresh_token'] as String);
          }

          if (data['user'] != null && data['user'] is Map<String, dynamic>) {
            _currentUser = User.fromJson(data['user'] as Map<String, dynamic>);
            _isAuthenticated = true;
          } else {
            await _loadProfile();
          }
          return true;
        } else {
          // Si el endpoint no retorna token directamente, intenta login
          return await _loginInternal(email: email, password: password);
        }
      } else {
        _setError(response.error ?? 'Error en el registro');
        return false;
      }
    } catch (e) {
      debugPrint('Error en registro: $e');
      _setError('Error de conexión o de datos: ${e.toString()}');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// Iniciar sesión
  Future<bool> login({
    required String email,
    required String password,
  }) async {
    _setLoading(true);
    _clearError();

    try {
      return await _loginInternal(email: email, password: password);
    } catch (e) {
      debugPrint('Error en login: $e');
      _setError('Error de conexión o de datos: ${e.toString()}');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// Helper interno para login (sin manejar _setLoading nuevamente)
  Future<bool> _loginInternal({
    required String email,
    required String password,
  }) async {
    final response = await _apiService.post(
      ApiConfig.loginUrl,
      {
        'email': email,
        'password': password,
      },
    );

    if (response.success && response.data != null) {
      final data = response.data;
      if (data is Map<String, dynamic> && data.containsKey('access_token')) {
        final accessToken = data['access_token'] as String;
        await _storageService.setAccessToken(accessToken);

        if (data['refresh_token'] != null) {
          await _storageService.setRefreshToken(data['refresh_token'] as String);
        }

        if (data['user'] != null && data['user'] is Map<String, dynamic>) {
          _currentUser = User.fromJson(data['user'] as Map<String, dynamic>);
          _isAuthenticated = true;
        } else {
          await _loadProfile();
        }
        return true;
      } else {
        _setError('Formato de respuesta del servidor no válido');
        return false;
      }
    } else {
      _setError(response.error ?? 'Credenciales inválidas');
      return false;
    }
  }

  /// Cerrar sesión
  Future<void> logout() async {
    _setLoading(true);

    try {
      // Notificar al backend para invalidar el token
      await _apiService.postAuth(ApiConfig.logoutUrl);
    } catch (e) {
      debugPrint('Error notificando logout al backend: $e');
    } finally {
      // Limpiar estado local en cualquier caso
      await _storageService.clearAll();
      _currentUser = null;
      _isAuthenticated = false;
      _setLoading(false);
    }
  }

  /// Cargar perfil del usuario actual
  Future<void> _loadProfile() async {
    try {
      final response = await _apiService.getAuth(ApiConfig.profileUrl);

      if (response.success && response.data != null && response.data is Map<String, dynamic>) {
        _currentUser = User.fromJson(response.data as Map<String, dynamic>);
        _isAuthenticated = true;
      } else {
        // Token inválido o expirado
        await _storageService.clearAll();
        _currentUser = null;
        _isAuthenticated = false;
      }
    } catch (e) {
      debugPrint('Error al cargar perfil: $e');
      await _storageService.clearAll();
      _currentUser = null;
      _isAuthenticated = false;
    }
  }

  /// Actualizar perfil
  Future<bool> updateProfile({String? fullName, String? email}) async {
    _setLoading(true);
    _clearError();

    try {
      final body = <String, dynamic>{};
      if (fullName != null) body['full_name'] = fullName;
      if (email != null) body['email'] = email;

      final response = await _apiService.putAuth(ApiConfig.profileUrl, body);

      if (response.success && response.data != null && response.data is Map<String, dynamic>) {
        _currentUser = User.fromJson(response.data as Map<String, dynamic>);
        return true;
      } else {
        _setError(response.error ?? 'Error al actualizar perfil');
        return false;
      }
    } catch (e) {
      debugPrint('Error al actualizar perfil: $e');
      _setError('Error al actualizar perfil: ${e.toString()}');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// Cambiar contraseña del usuario autenticado
  Future<Map<String, dynamic>> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    _setLoading(true);
    _clearError();

    try {
      final response = await _apiService.postAuth(
        ApiConfig.changePasswordUrl,
        {
          'current_password': currentPassword,
          'new_password': newPassword,
        },
      );

      if (response.success) {
        String msg = 'Contraseña actualizada exitosamente';
        if (response.data is Map<String, dynamic> &&
            response.data['message'] != null) {
          msg = response.data['message'] as String;
        }
        return {'success': true, 'message': msg};
      } else {
        final err = response.error ?? 'Error al cambiar contraseña';
        _setError(err);
        return {'success': false, 'message': err};
      }
    } catch (e) {
      debugPrint('Error al cambiar contraseña: $e');
      final err = 'Error de conexión al cambiar contraseña: ${e.toString()}';
      _setError(err);
      return {'success': false, 'message': err};
    } finally {
      _setLoading(false);
    }
  }


  // Helpers privados
  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void _setError(String message) {
    _error = message;
    notifyListeners();
  }

  void _clearError() {
    _error = null;
  }
}

