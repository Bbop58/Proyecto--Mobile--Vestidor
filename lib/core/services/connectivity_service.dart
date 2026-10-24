import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityService extends ChangeNotifier {
  final Connectivity _connectivity = Connectivity();
  late StreamSubscription<List<ConnectivityResult>> _subscription;
  bool _isOnline = true;
  bool _wasOffline = false;

  bool get isOnline => _isOnline;
  bool get wasOffline => _wasOffline;

  ConnectivityService() {
    _checkInitialStatus();
    _subscription = _connectivity.onConnectivityChanged.listen(_updateConnectionStatus);
  }

  Future<void> _checkInitialStatus() async {
    try {
      final results = await _connectivity.checkConnectivity();
      _updateConnectionStatus(results);
    } catch (e) {
      debugPrint('Error comprobando conectividad inicial: $e');
    }
  }

  void _updateConnectionStatus(List<ConnectivityResult> results) {
    final hasConnection = results.any((r) => r != ConnectivityResult.none);
    if (_isOnline && !hasConnection) {
      _wasOffline = true;
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
