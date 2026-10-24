import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../../config/api_config.dart';
import '../../services/api_service.dart';
import '../database/database_helper.dart';
import 'connectivity_service.dart';

class OfflineSyncService extends ChangeNotifier {
  final ApiService _apiService;
  final ConnectivityService _connectivityService;
  final DatabaseHelper _db = DatabaseHelper.instance;
  final Uuid _uuid = const Uuid();

  int _pendingCount = 0;
  bool _isSyncing = false;
  String? _lastError;
  Map<String, dynamic>? _lastSyncResult;

  int get pendingCount => _pendingCount;
  bool get isSyncing => _isSyncing;
  String? get lastError => _lastError;
  Map<String, dynamic>? get lastSyncResult => _lastSyncResult;

  OfflineSyncService(this._apiService, this._connectivityService) {
    refreshPendingCount();

    // Auto-sync listener: cuando se detecta conexión o reconexión
    _connectivityService.addListener(_onConnectivityChanged);
  }

  void _onConnectivityChanged() {
    if (_connectivityService.isOnline && _pendingCount > 0 && !_isSyncing) {
      debugPrint('[OFFLINE SYNC FLUTTER] Red recuperada. Iniciando auto-sincronización...');
      syncBatchNow();
      _connectivityService.clearReconnectedFlag();
    }
  }

  Future<int> refreshPendingCount() async {
    _pendingCount = await _db.getPendingCount();
    notifyListeners();
    return _pendingCount;
  }

  /// Registra una venta de mostrador en contingencia offline
  Future<String> saveOfflineSale({
    required String sucursalId,
    required List<Map<String, dynamic>> items,
    required double montoTotal,
    required double montoRecibido,
    required double cambio,
    String? cajeroId,
    String? clienteId,
    String metodoPago = 'EFECTIVO',
    String? notas,
  }) async {
    final clientOpId = _uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();

    final op = {
      'client_operation_id': clientOpId,
      'operation_type': 'VENTA_CONTADO_OFFLINE',
      'sucursal_id': sucursalId,
      'cajero_id': cajeroId,
      'cliente_id': clienteId,
      'fecha_local': now,
      'monto_total': montoTotal,
      'monto_recibido': montoRecibido,
      'cambio': cambio,
      'metodo_pago': metodoPago,
      'notas': notas ?? 'Venta registrada en contingencia móvil offline',
      'items_json': jsonEncode(items),
      'local_status': 'LOCAL_PENDIENTE',
      'server_receipt': null,
      'server_entity_id': null,
      'error_detail': null,
      'created_at': now,
    };

    await _db.insertPendingOperation(op);
    await refreshPendingCount();

    // Si hay conexión inmediata, enviar al servidor
    if (_connectivityService.isOnline) {
      syncBatchNow();
    }

    return clientOpId;
  }

  /// Registra una reserva en contingencia offline
  Future<String> saveOfflineReservation({
    required String sucursalId,
    required List<Map<String, dynamic>> items,
    required double montoTotal,
    String? clienteId,
    String? notas,
  }) async {
    final clientOpId = _uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();

    final op = {
      'client_operation_id': clientOpId,
      'operation_type': 'RESERVA_OFFLINE',
      'sucursal_id': sucursalId,
      'cliente_id': clienteId,
      'fecha_local': now,
      'monto_total': montoTotal,
      'monto_recibido': 0.0,
      'cambio': 0.0,
      'metodo_pago': 'RESERVA',
      'notas': notas ?? 'Reserva registrada en contingencia móvil offline',
      'items_json': jsonEncode(items),
      'local_status': 'LOCAL_PENDIENTE',
      'server_receipt': null,
      'server_entity_id': null,
      'error_detail': null,
      'created_at': now,
    };

    await _db.insertPendingOperation(op);
    await refreshPendingCount();

    if (_connectivityService.isOnline) {
      syncBatchNow();
    }

    return clientOpId;
  }

  /// Sincroniza todas las operaciones pendientes enviándolas en lote a POST /api/v1/sync/batch
  Future<bool> syncBatchNow() async {
    if (!_connectivityService.isOnline || _isSyncing) return false;

    final pendingOps = await _db.getPendingOperations();
    if (pendingOps.isEmpty) {
      await refreshPendingCount();
      return true;
    }

    _isSyncing = true;
    _lastError = null;
    notifyListeners();

    try {
      final operationsPayload = pendingOps.map((op) {
        final items = jsonDecode(op['items_json'] as String) as List;
        return {
          'client_operation_id': op['client_operation_id'],
          'operation_type': op['operation_type'],
          'sucursal_id': op['sucursal_id'],
          'cajero_id': op['cajero_id'],
          'cliente_id': op['cliente_id'],
          'fecha_local': op['fecha_local'],
          'monto_total': op['monto_total'],
          'monto_efectivo_recibido': op['monto_recibido'],
          'cambio_entregado': op['cambio'],
          'metodo_pago': op['metodo_pago'],
          'notas': op['notas'],
          'items': items.map((i) => {
            'variante_id': i['variante_id'] ?? i['id'],
            'cantidad': i['cantidad'] ?? 1,
            'precio_unitario': i['precio_unitario'] ?? i['precio'] ?? 0.0,
          }).toList(),
        };
      }).toList();

      final response = await _apiService.postAuth(
        ApiConfig.syncBatchUrl,
        {'operations': operationsPayload},
      );

      if (response.success && response.data != null) {
        _lastSyncResult = response.data as Map<String, dynamic>;
        final results = (_lastSyncResult!['results'] as List?) ?? [];

        for (final res in results) {
          final clientOpId = res['client_operation_id'];
          final status = res['status'];
          final receipt = res['receipt_number'];
          final entityId = res['server_entity_id'];
          final errorDetail = res['error_detail'];

          await _db.updateOperationStatus(clientOpId, {
            'local_status': status,
            'server_receipt': receipt,
            'server_entity_id': entityId,
            'error_detail': errorDetail,
          });
        }

        await refreshPendingCount();
        return true;
      } else {
        _lastError = response.error ?? 'Fallo al procesar el lote de sincronización en el servidor.';
        return false;
      }
    } catch (e) {
      _lastError = 'Excepción de red: $e';
      return false;
    } finally {
      _isSyncing = false;
      await refreshPendingCount();
      notifyListeners();
    }
  }

  Future<List<Map<String, dynamic>>> getAllOperations() async {
    return await _db.getAllOperations();
  }

  @override
  void dispose() {
    _connectivityService.removeListener(_onConnectivityChanged);
    super.dispose();
  }
}
