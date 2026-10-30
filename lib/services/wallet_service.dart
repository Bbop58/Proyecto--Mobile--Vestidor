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
  final StorageService _storage;
  final DatabaseHelper _db = DatabaseHelper.instance;
  final Uuid _uuid = const Uuid();

  UserWallet? _wallet;
  List<WalletTxItem> _transactions = [];
  bool _isLoading = false;
  String? _errorMessage;

  UserWallet? get wallet => _wallet;
  double get saldo => _wallet?.saldoActual ?? 0.0;
  List<WalletTxItem> get transactions => _transactions;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  WalletService(this._apiService, this._connectivity, this._storage) {
    _connectivity.addListener(_onConnectivityChanged);
  }

  void _onConnectivityChanged() {
    if (_connectivity.isOnline) {
      debugPrint('[WALLET SERVICE] Red reanudada. Sincronizando órdenes offline y refrescando saldo...');
      syncOfflineWalletOrders();
      fetchWallet();
    }
  }

  /// Carga el estado de la billetera (Online desde FastAPI o contingencia Offline desde SQLite)
  Future<void> fetchWallet({bool silent = false}) async {
    if (!silent) {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();
    }

    final userId = await _storage.getUserId() ?? 'current_user';

    if (_connectivity.isOnline) {
      try {
        final res = await _apiService.getAuth(ApiConfig.walletMeUrl);
        if (res.success && res.data != null) {
          final data = res.data as Map<String, dynamic>;
          _wallet = UserWallet.fromJson(data);

          // Persistir en SQLite local seguro
          await _db.saveLocalWallet(
            userId: _wallet!.userId.isNotEmpty ? _wallet!.userId : userId,
            saldo: _wallet!.saldoActual,
            nonce: _wallet!.nonceSecuencia,
            firma: _wallet!.firmaBalance,
            moneda: _wallet!.moneda,
          );

          await fetchHistory();
          _isLoading = false;
          notifyListeners();
          return;
        }
      } catch (e) {
        debugPrint('[WALLET SERVICE] Error consultando wallet online: $e');
      }
    }

    // Modo Offline o fallo de red: Recuperar de SQLite
    try {
      final localData = await _db.getLocalWallet(userId);
      if (localData != null) {
        _wallet = UserWallet(
          id: 'local_${localData['user_id']}',
          userId: localData['user_id'].toString(),
          saldoActual: (localData['saldo'] as num).toDouble(),
          saldoRetenido: 0.0,
          nonceSecuencia: (localData['nonce'] as num).toInt(),
          firmaBalance: localData['firma']?.toString() ?? '',
          moneda: localData['moneda']?.toString() ?? 'BOB',
          ultimoSyncAt: localData['updated_at'] != null
              ? DateTime.tryParse(localData['updated_at'].toString())
              : null,
        );
      }

      final localTxs = await _db.getLocalWalletTransactions(userId);
      _transactions = localTxs.map((t) => WalletTxItem.fromJson(t)).toList();
    } catch (e) {
      debugPrint('[WALLET SERVICE] Error cargando wallet local SQLite: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Carga el historial de movimientos de la billetera
  Future<void> fetchHistory() async {
    final userId = await _storage.getUserId() ?? 'current_user';
    if (_connectivity.isOnline) {
      try {
        final res = await _apiService.getAuth(ApiConfig.walletHistoryUrl);
        if (res.success && res.data != null) {
          final list = res.data as List;
          _transactions = list.map((item) => WalletTxItem.fromJson(item as Map<String, dynamic>)).toList();

          // Guardar copia local en SQLite
          final txsToCache = list.map((item) {
            final m = item as Map<String, dynamic>;
            return {
              'id': m['id']?.toString() ?? _uuid.v4(),
              'user_id': userId,
              'tipo': m['tipo'],
              'monto': m['monto'],
              'saldo_anterior': m['saldo_anterior'],
              'saldo_posterior': m['saldo_posterior'],
              'descripcion': m['descripcion'],
              'created_at': m['created_at'],
            };
          }).toList();
          await _db.saveLocalWalletTransactions(txsToCache);
          notifyListeners();
          return;
        }
      } catch (e) {
        debugPrint('[WALLET SERVICE] Error consultando historial online: $e');
      }
    }

    // Fallback SQLite
    final localTxs = await _db.getLocalWalletTransactions(userId);
    _transactions = localTxs.map((t) => WalletTxItem.fromJson(t)).toList();
    notifyListeners();
  }

  /// Inicia recarga de saldo mediante pasarela PayPal Sandbox
  Future<Map<String, dynamic>?> initiatePayPalTopup(double amountBob) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final res = await _apiService.postAuth(
        ApiConfig.walletTopupPaypalUrl,
        {'monto_bob': amountBob},
      );

      _isLoading = false;
      notifyListeners();

      if (res.success && res.data != null) {
        return res.data as Map<String, dynamic>;
      } else {
        _errorMessage = res.error ?? 'Error iniciando recarga con PayPal';
        return null;
      }
    } catch (e) {
      _isLoading = false;
      _errorMessage = 'Excepción al conectar con PayPal: $e';
      notifyListeners();
      return null;
    }
  }

  /// Realiza el cobro con saldo de la Billetera (Soporta Offline y Online)
  Future<Map<String, dynamic>> payWithWallet({
    required String sucursalId,
    required List<Map<String, dynamic>> items,
    required double totalAmount,
  }) async {
    final userId = await _storage.getUserId() ?? 'cliente_anon';

    // 1. Verificación de saldo local garantizado
    if (_wallet == null || _wallet!.saldoActual < totalAmount) {
      final current = _wallet?.saldoActual ?? 0.0;
      throw Exception(
        'Saldo insuficiente en tu Billetera Virtual.\nSaldo disponible: Bs. ${current.toStringAsFixed(2)}\nTotal a pagar: Bs. ${totalAmount.toStringAsFixed(2)}',
      );
    }

    final clientOpId = _uuid.v4();
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final nuevoSaldo = _wallet!.saldoActual - totalAmount;
    final nuevoNonce = _wallet!.nonceSecuencia + 1;

    // 2. Descuento atómico en SQLite local
    await _db.updateLocalWalletBalance(
      userId: userId,
      nuevoSaldo: nuevoSaldo,
      nuevoNonce: nuevoNonce,
    );

    // Registrar transacción en el histórico local
    final txLocal = {
      'id': _uuid.v4(),
      'user_id': userId,
      'tipo': 'PAGO_VENTA_OFFLINE',
      'monto': -totalAmount,
      'saldo_anterior': _wallet!.saldoActual,
      'saldo_posterior': nuevoSaldo,
      'descripcion': 'Pago de pedido con Billetera Virtual (${items.length} prendas)',
      'created_at': nowIso,
    };
    await _db.saveLocalWalletTransactions([txLocal]);

    // 3. Registrar orden en la cola de contingencia offline de la billetera
    final walletOrder = {
      'client_operation_id': clientOpId,
      'cliente_id': userId,
      'sucursal_id': sucursalId,
      'monto_total': totalAmount,
      'nonce_usado': _wallet!.nonceSecuencia,
      'firma_usada': _wallet!.firmaBalance,
      'items_json': jsonEncode(items),
      'fecha_local': nowIso,
      'status': 'PENDIENTE',
      'server_receipt': null,
      'error_detail': null,
      'created_at': nowIso,
    };
    await _db.insertOfflineWalletOrder(walletOrder);

    // Actualizar estado en memoria
    _wallet = UserWallet(
      id: _wallet!.id,
      userId: _wallet!.userId,
      saldoActual: nuevoSaldo,
      saldoRetenido: _wallet!.saldoRetenido,
      nonceSecuencia: nuevoNonce,
      firmaBalance: _wallet!.firmaBalance,
      moneda: _wallet!.moneda,
      ultimoSyncAt: DateTime.now(),
    );
    _transactions.insert(0, WalletTxItem.fromJson(txLocal));
    notifyListeners();

    // 4. Si hay red, sincronizar de inmediato
    if (_connectivity.isOnline) {
      syncOfflineWalletOrders();
    }

    return {
      'success': true,
      'client_operation_id': clientOpId,
      'nuevo_saldo': nuevoSaldo,
      'offline_queued': !_connectivity.isOnline,
    };
  }

  /// Sincroniza la cola de órdenes de billetera contra el servidor central
  Future<bool> syncOfflineWalletOrders() async {
    if (!_connectivity.isOnline) return false;

    final pending = await _db.getPendingOfflineWalletOrders();
    if (pending.isEmpty) return true;

    try {
      final ordersPayload = pending.map((row) {
        final items = jsonDecode(row['items_json'] as String) as List;
        return {
          'client_operation_id': row['client_operation_id'],
          'sucursal_id': row['sucursal_id'],
          'monto_total': row['monto_total'],
          'items': items.map((i) => {
            'variante_id': i['variante_id'] ?? i['id'],
            'cantidad': i['cantidad'] ?? 1,
            'precio_unitario': i['precio_unitario'] ?? i['precio'] ?? 0.0,
          }).toList(),
          'fecha_local': row['fecha_local'],
          'nonce': row['nonce_usado'] ?? 0,
          'firma_cliente': row['firma_usada'] ?? '',
        };
      }).toList();

      final res = await _apiService.postAuth(
        ApiConfig.walletSyncOfflineUrl,
        {'orders': ordersPayload},
      );

      if (res.success && res.data != null) {
        final data = res.data as Map<String, dynamic>;
        final results = (data['results'] as List?) ?? [];

        for (final r in results) {
          final opId = r['client_operation_id']?.toString() ?? '';
          final status = r['status']?.toString() ?? 'ERROR';
          final receipt = r['receipt_number']?.toString();
          final err = r['error_detail']?.toString();

          await _db.updateOfflineWalletOrderStatus(
            opId,
            status: status,
            serverReceipt: receipt,
            errorDetail: err,
          );
        }

        // Refrescar saldo oficial reconciliado del servidor
        await fetchWallet(silent: true);
        return true;
      }
    } catch (e) {
      debugPrint('[WALLET SERVICE] Error sincronizando órdenes offline: $e');
    }
    return false;
  }

  @override
  void dispose() {
    _connectivity.removeListener(_onConnectivityChanged);
    super.dispose();
  }
}

