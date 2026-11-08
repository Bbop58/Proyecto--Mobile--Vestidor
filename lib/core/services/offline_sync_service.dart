import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../config/api_config.dart';
import '../../services/api_service.dart';
import '../../services/wallet_service.dart';
import '../database/database_helper.dart';
import 'connectivity_service.dart';
import 'offline_authorization_service.dart';

class OfflineSyncService extends ChangeNotifier {
  final ApiService _apiService;
  final ConnectivityService _connectivityService;
  final WalletService? _walletService;
  final DatabaseHelper _db = DatabaseHelper.instance;
  final Uuid _uuid = const Uuid();

  final Set<String> _running = {};
  Timer? _retryTimer;
  int _failures = 0;
  bool _paused = false;
  bool _disposed = false;
  int _pendingCount = 0;
  bool _isSyncing = false;
  String? _lastError;
  Map<String, dynamic>? _lastSyncResult;

  int get pendingCount => _pendingCount;
  bool get isSyncing => _isSyncing;
  String? get lastError => _lastError ?? _walletService?.errorMessage;
  Map<String, dynamic>? get lastSyncResult => _lastSyncResult;

  OfflineSyncService(this._apiService, this._connectivityService, {WalletService? walletService})
      // Keep the public named argument separate from the private dependency.
      // ignore: prefer_initializing_formals
      : _walletService = walletService {
    DatabaseHelper.scopeChanges.addListener(_onScopeChanged);
    _walletService?.addListener(_onWalletChanged);
    refreshPendingCount();

    // Auto-sync listener: cuando se detecta conexión o reconexión
    _connectivityService.addListener(_onConnectivityChanged);
  }

  void _onWalletChanged() {
    refreshPendingCount();
  }

  void _onScopeChanged() {
    _retryTimer?.cancel();
    _paused = false;
    _isSyncing = false;
    _pendingCount = 0;
    _lastError = null;
    _lastSyncResult = null;
    notifyListeners();
    refreshPendingCount();
  }

  void _onConnectivityChanged() {
    if (_connectivityService.isOnline && _pendingCount > 0 && !_isSyncing) {
      debugPrint(
        '[OFFLINE SYNC FLUTTER] Red recuperada. Iniciando auto-sincronización...',
      );
      syncBatchNow();
      _connectivityService.clearReconnectedFlag();
    }
  }

  Future<int> refreshPendingCount() async {
    final scope = DatabaseHelper.scope;
    if (scope == null || _disposed) return 0;
    final db = _db.forScope(scope);
    final count = await db.getPendingCount() +
        (await db.getPendingOfflineWalletOrders()).length;
    if (!_disposed && scope == DatabaseHelper.scope) { _pendingCount = count; notifyListeners(); }
    return count;
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
    final scope = DatabaseHelper.scope;
    if (scope == null) {
      throw StateError('Inicia sesión para registrar operaciones');
    }
    final db = _db.forScope(scope);
    final grant=await OfflineAuthorizationService(_apiService).take('SYNC',online:_connectivityService.isOnline);
    final clientOpId = grant?['client_operation_id']?.toString() ?? _uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();

    final op = {
      'client_operation_id': clientOpId,
      'offline_authorization':grant?['authorization'],
      'operation_type': 'VENTA_CONTADO_OFFLINE',
      'sucursal_id': sucursalId,
      'cajero_id': cajeroId ?? scope.split(':').last,
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

    await db.insertPendingOperation(op);
    if (scope != DatabaseHelper.scope) throw StateError("La sesión cambió; operación conservada con su propietario");
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
    final scope = DatabaseHelper.scope;
    if (scope == null) {
      throw StateError('Inicia sesión para registrar operaciones');
    }
    final db = _db.forScope(scope);
    final grant=await OfflineAuthorizationService(_apiService).take('SYNC',online:_connectivityService.isOnline);
    final clientOpId = grant?['client_operation_id']?.toString() ?? _uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();

    final op = {
      'client_operation_id': clientOpId,
      'offline_authorization':grant?['authorization'],
      'operation_type': 'RESERVA_OFFLINE',
      'sucursal_id': sucursalId,
      'cliente_id': clienteId ?? scope.split(':').last,
      'fecha_hora_esperada': DateTime.parse(now).add(const Duration(hours:24)).toIso8601String(),
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

    await db.insertPendingOperation(op);
    if (scope != DatabaseHelper.scope) throw StateError("La sesión cambió; operación conservada con su propietario");
    await refreshPendingCount();

    if (_connectivityService.isOnline) {
      syncBatchNow();
    }

    return clientOpId;
  }

  /// Sincroniza todas las operaciones pendientes enviándolas en lote a POST /api/v1/sync/batch
  void _retry(String scope) {
    _retryTimer?.cancel();
    final seconds = 1 << _failures.clamp(0,6); _failures++;
    _retryTimer = Timer(Duration(seconds: seconds > 60 ? 60 : seconds), () {
      if (!_disposed && scope == DatabaseHelper.scope && !_paused) syncBatchNow();
    });
  }

  static Map<String,dynamic> payload(Map<String,dynamic> op) => {
    'client_operation_id':op['client_operation_id'], 'offline_authorization':op['offline_authorization'], 'operation_type':op['operation_type'],
    'sucursal_id':op['sucursal_id'], 'cajero_id':op['cajero_id'], 'cliente_id':op['cliente_id'],
    'fecha_local':op['fecha_local'], 'monto_total':op['monto_total'],
    'fecha_hora_esperada':op['fecha_hora_esperada'], 'codigo_cupon':op['codigo_cupon'],
    'supersedes_operation_id':op['supersedes_operation_id'],
    'monto_efectivo_recibido':op['monto_recibido'], 'cambio_entregado':op['cambio'],
    'metodo_pago':op['metodo_pago'], 'notas':op['notas'],
    'items': (jsonDecode(op['items_json'] as String) as List).map((i) => {
      'variante_id':i['variante_id'] ?? i['id'], 'cantidad':i['cantidad'] ?? 1,
      'precio_unitario':i['precio_unitario'] ?? i['precio'] ?? 0.0}).toList(),
  };

  Future<bool> syncBatchNow({bool force = false}) async {
    final scope = DatabaseHelper.scope;
    if (_disposed || scope == null || !_connectivityService.isOnline || _running.contains(scope) || (_paused && !force)) return false;
    _running.add(scope); _isSyncing = true; _lastError = null;
    if (force) _paused = false;
    notifyListeners();
    final db = _db.forScope(scope);
    try {
      if (!await _apiService.prepareSession(expectedScope:scope)) {
        if (!_disposed && scope == DatabaseHelper.scope) {
          _lastError = _apiService.sessionCoordinator?.notice ?? 'Revalida tu sesión para sincronizar; pendientes conservados.';
          if (_apiService.sessionCoordinator?.hasIdentity == true) _retry(scope);
        }
        return false;
      }
      // Keep the wallet's signed protocol and mutex; never send it as a cash sale.
      final walletSynced = _walletService == null ||
          await _walletService.syncOfflineWalletOrders(force: force);
      if (_disposed || scope != DatabaseHelper.scope) return false;
      final pending = (await db.getPendingOperations()).take(100).toList();
      if (_disposed || scope != DatabaseHelper.scope) return false;
      if (pending.isEmpty) return walletSynced;
      final response = await _apiService.postAuth(ApiConfig.syncBatchUrl, {'operations':pending.map(payload).toList()}, null, scope);
      if (_disposed || scope != DatabaseHelper.scope) return false;
      if (!response.success || response.data is! Map) {
        _lastError = response.error ?? 'No se confirmó el lote';
        if ([400,401,403,422].contains(response.statusCode)) { _paused = true; }
        else { _retry(scope); }
        return false;
      }
      final result = Map<String,dynamic>.from(response.data as Map);
      await db.applySyncResults(pending,result);
      if (_disposed || scope != DatabaseHelper.scope) return false;
      _lastSyncResult = result; _failures = 0;
      final review=(result['results'] as List).any((r)=>r['requires_review']==true);
      if(review) {_paused=true;_lastError='REVISION_REQUERIDA: pendientes conservados; revisa la autorización contractual';}
      else if ((result['results'] as List).any((r) => r['status']=='REINTENTAR') || (await db.getPendingOperations()).isNotEmpty) { _retry(scope); }
      return walletSynced;
    } catch (e) {
      if (!_disposed && scope == DatabaseHelper.scope) { _lastError = 'Pendientes conservados: $e'; _retry(scope); }
      return false;
    } finally {
      _running.remove(scope);
      if (!_disposed && scope == DatabaseHelper.scope) {
        _isSyncing = false; await refreshPendingCount();
      }
    }
  }

  Future<List<Map<String,dynamic>>> getAllOperations() async {
    final scope = DatabaseHelper.scope;
    if (scope == null) return [];
    final db=_db.forScope(scope);
    final result = await db.getAllOperations();
    final walletRows=await db.getAllWalletOrders();
    return scope == DatabaseHelper.scope ? [...result,...walletRows.map((r)=>{
      ...r,'operation_type':'COMPRA_BILLETERA_OFFLINE',
      'local_status':r['status']=='PENDIENTE'?'LOCAL_PENDIENTE':r['status']})] : [];
  }

  Future<void> retryRejected(Map<String,dynamic> op) async {
    final scope = DatabaseHelper.scope;
    if (scope == null || !_connectivityService.isOnline) throw StateError('Conéctate para verificar la operación original');
    final response = await _apiService.getAuth('${ApiConfig.syncBatchUrl.replaceFirst('/batch','')}/operations/${op['client_operation_id']}');
    if (scope != DatabaseHelper.scope) return;
    final status = response.data;
    if (!response.success || status is! Map || status['server_entity_id'] != null || !['CONFLICTO','RECHAZADA_POR_STOCK'].contains(status['status'])) {
      throw StateError('Revisa el efecto original antes de crear otra operación');
    }
    final retryDate = DateTime.now().toUtc();
    final replacement = {...op,'client_operation_id':_uuid.v4(), 'fecha_local':retryDate.toIso8601String(),
      'server_receipt':null,'server_entity_id':null,'error_detail':null,'synced_at':null,'replacement_id':null,
      if (op['operation_type']=='RESERVA_OFFLINE') 'fecha_hora_esperada':retryDate.add(const Duration(hours:24)).toIso8601String()};
    await _db.forScope(scope).replaceRejectedOperation(op['client_operation_id'].toString(),replacement);
    if (scope == DatabaseHelper.scope) await syncBatchNow(force:true);
  }

  @override
  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
    DatabaseHelper.scopeChanges.removeListener(_onScopeChanged);
    _walletService?.removeListener(_onWalletChanged);
    _connectivityService.removeListener(_onConnectivityChanged);
    super.dispose();
  }
}
