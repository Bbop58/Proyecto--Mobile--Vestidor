import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../config/api_config.dart';
import '../models/wallet.dart';
import 'api_service.dart';
import 'storage_service.dart';
import '../core/services/connectivity_service.dart';
import '../core/database/database_helper.dart';

class WalletService extends ChangeNotifier {
  final ApiService _apiService;
  final ConnectivityService _connectivity;
  final Set<String> _running = {};
  Timer? _retryTimer;
  int _failures = 0;
  bool _paused = false;
  bool _disposed = false;
  final DatabaseHelper _db = DatabaseHelper.instance;
  final Uuid _uuid = const Uuid();

  UserWallet? _wallet;
  List<WalletTxItem> _transactions = [];
  bool _isLoading = false;
  String? _errorMessage;

  UserWallet? get wallet =>
      _wallet?.userId == DatabaseHelper.scope?.split(':').last ? _wallet : null;
  double get saldo => wallet == null ? 0.0 : wallet!.saldoDisponible;
  List<WalletTxItem> get transactions => wallet == null ? [] : _transactions;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  WalletService(this._apiService, this._connectivity, StorageService storage) {
    DatabaseHelper.scopeChanges.addListener(_onScopeChanged);
    _connectivity.addListener(_onConnectivityChanged);
  }

  void _onScopeChanged() {
    _retryTimer?.cancel();
    _paused = false;
    _isLoading = false;
    _wallet = null;
    _transactions = [];
    _errorMessage = null;
    notifyListeners();
  }

  void _onConnectivityChanged() {
    if (_connectivity.isOnline && !_paused) _reconnect();
  }

  Future<void> _reconnect() async {
    await syncOfflineWalletOrders();
    if (!_disposed) await fetchWallet(silent: true);
  }

  Future<void> _hydrate(String scope, DatabaseHelper db) async {
    final user = scope.split(':').last;
    final row = await db.getLocalWallet(user);
    final pending = await db.getPendingWalletTotal(user);
    final history = await db.getLocalWalletTransactions(user);
    if (_disposed || scope != DatabaseHelper.scope) return;
    _wallet = row == null || row['server_validated'] != 1 ? null : UserWallet(
      id: 'local_$user', userId: user, saldoActual: (row['saldo'] as num).toDouble(),
      saldoRetenido: (row['saldo_retenido'] as num?)?.toDouble() ?? 0,
      saldoPendiente: pending, nonceSecuencia: (row['nonce'] as num).toInt(),
      firmaBalance: row['firma'].toString(), moneda: row['moneda']?.toString() ?? 'BOB');
    if(row!=null && row['server_validated']!=1) _errorMessage='Conéctate para validar la billetera; tus datos locales se conservan';
    _transactions = history.map(WalletTxItem.fromJson).toList();
    notifyListeners();
  }

  Future<void> fetchWallet({bool silent = false}) async {
    final scope = DatabaseHelper.scope;
    if (scope == null || _disposed) return;
    final db = _db.forScope(scope);
    final user = scope.split(':').last;
    if (!silent) { _isLoading = true; _errorMessage = null; notifyListeners(); }
    try {
      if (_connectivity.isOnline) {
        final res = await _apiService.getAuth(ApiConfig.walletMeUrl);
        if (_disposed || scope != DatabaseHelper.scope) return;
        if (res.success && res.data != null) {
          final central = UserWallet.fromJson(Map<String,dynamic>.from(res.data as Map));
          if (central.userId != user || !central.saldoActual.isFinite || central.saldoActual < 0 ||
            !central.saldoRetenido.isFinite || central.saldoRetenido < 0 || central.saldoRetenido > central.saldoActual ||
            central.nonceSecuencia < 0 || central.firmaBalance.isEmpty) { throw const FormatException('Billetera no verificable'); }
          await db.saveLocalWallet(userId:user, saldo:central.saldoActual,
            saldoRetenido:central.saldoRetenido, nonce:central.nonceSecuencia,
            firma:central.firmaBalance, moneda:central.moneda);
          if (!_disposed && scope == DatabaseHelper.scope) _paused = false;
        } else if ([401,403,409].contains(res.statusCode)) {
          await db.invalidateWallet(user);
          if (scope == DatabaseHelper.scope && !_disposed) {
            _wallet = null; _errorMessage = res.error; _paused = true;
          }
          return;
        }
      }
      await _hydrate(scope,db);
      if (_connectivity.isOnline && scope == DatabaseHelper.scope) await fetchHistory();
    } catch (_) {
      await _hydrate(scope,db);
    } finally {
      if (!_disposed && scope == DatabaseHelper.scope) { _isLoading = false; notifyListeners(); }
    }
  }

  Future<void> fetchHistory() async {
    final scope = DatabaseHelper.scope;
    if (scope == null || _disposed) return;
    final user = scope.split(':').last;
    final db = _db.forScope(scope);
    try {
      if (_connectivity.isOnline) {
        final res = await _apiService.getAuth(ApiConfig.walletHistoryUrl);
        if (_disposed || scope != DatabaseHelper.scope) return;
        if (res.success && res.data is List) {
          await db.saveLocalWalletTransactions((res.data as List).map((item) {
            final m = Map<String,dynamic>.from(item as Map);
            return {'id':m['id'], 'user_id':user, 'tipo':m['tipo'], 'monto':m['monto'],
              'saldo_anterior':m['saldo_anterior'], 'saldo_posterior':m['saldo_posterior'],
              'descripcion':m['descripcion'], 'created_at':m['created_at']};
          }).toList());
        }
      }
    } catch (_) { /* Keep the durable local history on network failure. */ }
    await _hydrate(scope,db);
  }

  Future<Map<String,dynamic>?> initiatePayPalTopup(double amountBob) async {
    final scope=DatabaseHelper.scope;
    if(scope==null || _disposed) return null;
    _isLoading=true;_errorMessage=null;notifyListeners();
    try {
      final response=await _apiService.postAuth(ApiConfig.walletTopupPaypalUrl,{'monto_bob':amountBob},null,scope);
      if(_disposed || scope!=DatabaseHelper.scope) return null;
      if(response.success && response.data is Map) return Map<String,dynamic>.from(response.data as Map);
      _errorMessage=response.error ?? 'No se pudo iniciar la recarga';return null;
    } catch(_) { return null; }
    finally { if(!_disposed && scope==DatabaseHelper.scope) { _isLoading=false;notifyListeners(); } }
  }

  Future<bool> confirmPayPalTopup({required String orderId,required double amountBob,required double amountUsd}) async {
    final scope=DatabaseHelper.scope;
    if(scope==null || _disposed) return false;
    final db=_db.forScope(scope);
    _isLoading=true;_errorMessage=null;notifyListeners();
    try {
      final response=await _apiService.postAuth(ApiConfig.walletTopupPaypalUrl,
        {'order_id':orderId,'monto_bob':amountBob,'monto_usd':amountUsd},const Duration(seconds:40),scope);
      if(_disposed || scope!=DatabaseHelper.scope) return false;
      if(!response.success || response.data is! Map) { _errorMessage=response.error;return false; }
      final central=UserWallet.fromJson(Map<String,dynamic>.from(response.data as Map));
      if(central.userId!=scope.split(':').last || central.firmaBalance.isEmpty) throw const FormatException('Propietario o comprobante incorrecto');
      await db.saveLocalWallet(userId:central.userId,saldo:central.saldoActual,saldoRetenido:central.saldoRetenido,
        nonce:central.nonceSecuencia,firma:central.firmaBalance,moneda:central.moneda);
      await _hydrate(scope,db);
      return scope==DatabaseHelper.scope;
    } catch(_) { return false; }
    finally { if(!_disposed && scope==DatabaseHelper.scope) { _isLoading=false;notifyListeners(); } }
  }

  /// Realiza el cobro con saldo de la Billetera (Soporta Offline y Online)
  Future<Map<String, dynamic>> payWithWallet({
    required String sucursalId,
    required List<Map<String, dynamic>> items,
    required double totalAmount,
    String? codigoCupon,
  }) async {
    final scope = DatabaseHelper.scope;
    final currentWallet = wallet;
    if (scope == null || currentWallet == null) {
      throw StateError('Inicia sesión y carga tu billetera');
    }
    final db = _db.forScope(scope);
    final userId = scope.split(':').last;

    if (!totalAmount.isFinite || totalAmount <= 0 || (currentWallet.saldoDisponible*100).round() < (totalAmount*100).round()) {
      throw Exception('Saldo disponible insuficiente');
    }
    final clientOpId = _uuid.v4();
    final nowIso = DateTime.now().toUtc().toIso8601String();
    await db.recordWalletOrder({
      'client_operation_id': clientOpId, 'cliente_id': userId, 'sucursal_id': sucursalId,
      'monto_total': totalAmount, 'codigo_cupon': codigoCupon,
      'nonce_usado': currentWallet.nonceSecuencia, 'firma_usada': currentWallet.firmaBalance,
      'items_json': jsonEncode(items), 'fecha_local': nowIso, 'status': 'PENDIENTE',
      'server_receipt': null, 'error_detail': null, 'created_at': nowIso,
    });
    if (_disposed || scope != DatabaseHelper.scope) {
      return {'success': false, 'error': 'La sesión cambió; la operación permanece con su propietario'};
    }
    await _hydrate(scope,db);
    // A local debit is provisional until this exact operation has a server receipt.
    if (_connectivity.isOnline) {
      await syncOfflineWalletOrders();
      if (scope != DatabaseHelper.scope) {
        return {'success': false, 'error': 'La sesión cambió durante el pago'};
      }
      final result = await db.getOfflineWalletOrder(clientOpId);
      final status = result?['status']?.toString();
      if (status == 'CONFIRMADA') {
        return {'success': true, 'client_operation_id': clientOpId,
          'offline_queued': false, 'server_receipt': result?['server_receipt']};
      }
      if (status != null && status != 'PENDIENTE') {
        return {'success': false, 'client_operation_id': clientOpId,
          'error': result?['error_detail'] ?? 'El servidor rechazó la compra'};
      }
    }
    return {'success': true, 'client_operation_id': clientOpId,
      'nuevo_saldo': saldo, 'offline_queued': true};
  }

  /// Sincroniza la cola de órdenes de billetera contra el servidor central
  void _scheduleRetry(String scope) {
    _retryTimer?.cancel();
    final seconds = 1 << _failures.clamp(0, 6);
    _failures++;
    _retryTimer = Timer(Duration(seconds: seconds > 60 ? 60 : seconds), () {
      if (!_disposed && scope == DatabaseHelper.scope && !_paused) syncOfflineWalletOrders();
    });
  }

  Future<bool> syncOfflineWalletOrders({bool force = false}) async {
    final scope = DatabaseHelper.scope;
    if (_disposed || scope == null || !_connectivity.isOnline || _running.contains(scope) || (_paused && !force)) return false;
    _running.add(scope); // Before the first database await.
    if (force) _paused = false;
    final db = _db.forScope(scope);
    try {
      final pending = (await db.getPendingOfflineWalletOrders()).take(100).toList();
      if (_disposed || scope != DatabaseHelper.scope) return false;
      if (pending.isEmpty) return true;
      final ordersPayload = pending.map((row) => {
        'client_operation_id':row['client_operation_id'], 'sucursal_id':row['sucursal_id'],
        'monto_total':row['monto_total'], 'codigo_cupon':row['codigo_cupon'],
        'items':(jsonDecode(row['items_json'] as String) as List).map((i) => {
          'variante_id':i['variante_id'] ?? i['id'], 'cantidad':i['cantidad'] ?? 1,
          'precio_unitario':i['precio_unitario'] ?? i['precio'] ?? 0.0}).toList(),
        'fecha_local':row['fecha_local'], 'nonce':row['nonce_usado'],
        'firma_cliente':row['firma_usada'], 'codigo_autorizacion_offline':row['firma_usada'],
      }).toList();
      final res = await _apiService.postAuth(ApiConfig.walletSyncOfflineUrl, {'orders':ordersPayload}, null, scope);
      if (_disposed || scope != DatabaseHelper.scope) return false;
      if (!res.success || res.data is! Map) {
        _errorMessage = res.error ?? 'No se confirmó la sincronización';
        if ([400,401,403,409,422].contains(res.statusCode)) { _paused = true; }
        else { _scheduleRetry(scope); }
        return false;
      }
      final data = Map<String,dynamic>.from(res.data as Map);
      await db.applyWalletSyncResults(scope.split(':').last,pending,data);
      if (_disposed || scope != DatabaseHelper.scope) return false;
      await _hydrate(scope,db);
      final rejected=(data['results'] as List).where((r)=>r['status']!='CONFIRMADA' && r['status']!='REINTENTAR').toList();
      _errorMessage=rejected.isEmpty?null:'${rejected.length} compra(s) rechazadas. Revisa el historial de sincronización: ${rejected.first['error_detail'] ?? rejected.first['status']}';
      notifyListeners();
      _failures = 0;
      if ((data['results'] as List).any((r) => r['status']=='REINTENTAR') || (await db.getPendingOfflineWalletOrders()).isNotEmpty) {
        _scheduleRetry(scope);
      }
      return true;
    } catch (e) {
      if (!_disposed && scope == DatabaseHelper.scope) {
        _errorMessage = 'Pendientes conservados: $e'; _scheduleRetry(scope);
      }
      return false;
    } finally { _running.remove(scope); }
  }

  @override
  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
    DatabaseHelper.scopeChanges.removeListener(_onScopeChanged);
    _connectivity.removeListener(_onConnectivityChanged);
    super.dispose();
  }
}
