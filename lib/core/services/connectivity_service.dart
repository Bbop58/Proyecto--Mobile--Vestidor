import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../../services/local_notification_service.dart';

class ConnectivityService extends ChangeNotifier {
  final Connectivity _connectivity = Connectivity();
  late StreamSubscription<List<ConnectivityResult>> _subscription;
  bool _isOnline = true;
  bool _wasOffline = false;
  bool _isInitialized = false;

  bool get isOnline => _isOnline;
  bool get wasOffline => _wasOffline;

  ConnectivityService() {
    _initService();
  }

  Future<void> _initService() async {
    try {
      final results = await _connectivity.checkConnectivity();
      final hasConnection = results.any((r) => r != ConnectivityResult.none);
      _isOnline = hasConnection;
      _isInitialized = true;
      notifyListeners();
    } catch (e) {
      debugPrint('Error comprobando conectividad inicial: $e');
      _isInitialized = true;
    }

    _subscription = _connectivity.onConnectivityChanged.listen(_updateConnectionStatus);
  }

  void _updateConnectionStatus(List<ConnectivityResult> results) {
    final hasConnection = results.any((r) => r != ConnectivityResult.none);

    if (_isInitialized) {
      // Cambio de Online -> Offline
      if (_isOnline && !hasConnection) {
        _wasOffline = true;
        LocalNotificationService.showNotification(
          id: 9991,
          title: '📡 Modo Sin Conexión Activado',
          body: 'Estás desconectado. Puedes seguir usando el Catálogo en Caché, Billetera Offline y Chatbot Local.',
        );
      }
      // Cambio de Offline -> Online
      else if (!_isOnline && hasConnection) {
        LocalNotificationService.showNotification(
          id: 9992,
          title: '🟢 Conexión Restablecida',
          body: 'Conectado a la nube. Sincronizando transacciones offline y actualizando catálogo...',
        );
      }
    }

    _isOnline = hasConnection;
    notifyListeners();
  }

  void clearReconnectedFlag() {
    _wasOffline = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
