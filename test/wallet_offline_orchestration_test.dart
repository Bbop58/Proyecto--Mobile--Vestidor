import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:mobile/core/database/database_helper.dart';
import 'package:mobile/core/services/connectivity_service.dart';
import 'package:mobile/core/services/offline_sync_service.dart';
import 'package:mobile/services/api_service.dart';
import 'package:mobile/services/storage_service.dart';
import 'package:mobile/services/wallet_service.dart';
import 'package:mobile/screens/offline/offline_sync_screen.dart';

class _Network extends ChangeNotifier implements ConnectivityService {
  bool online = false;
  @override bool get isOnline => online;
  @override bool get wasOffline => false;
  @override void clearReconnectedFlag() {}
  void reconnect() { online = true; notifyListeners(); }
}

class _Api extends ApiService {
  _Api() : super(StorageService());
  int posts = 0;
  String outcome = 'CONFIRMADA';
  double balance = 290;
  int nonce = 4;
  int? failureCode;
  @override Future<ApiResponse> getAuth(String url) async => ApiResponse(success: true, statusCode: 200,
    data: url.endsWith('/history') ? [] : {'id': 'wallet', 'user_id': 'user',
      'saldo_actual': balance, 'saldo_retenido': 0, 'nonce_secuencia': nonce,
      'firma_balance': 'proof', 'moneda': 'BOB'});
  @override Future<ApiResponse> postAuth(String url, [Map<String,dynamic>? body, Duration? timeout, String? expectedScope]) async {
    if(url.endsWith('/authorizations')) return ApiResponse(success:true,statusCode:200,data:{'grants':[]});
    posts++;
    if (failureCode != null) return ApiResponse(success: false, statusCode: failureCode!, error: 'Sesión vencida');
    expect(body!.containsKey('orders'), isTrue, reason: 'Wallet uses its own signed protocol');
    final id = (body['orders'] as List).single['client_operation_id'];
    balance = outcome == 'CONFIRMADA' ? 270 : 290;
    nonce = 5;
    return ApiResponse(success: true, statusCode: 200, data: {
      'nuevo_saldo': outcome == 'CONFIRMADA' ? 270.0 : 290.0,
      'saldo_retenido': 0.0, 'nuevo_nonce': 5, 'nueva_firma': 'new-proof',
      'results': [{'client_operation_id': id, 'status': outcome,
        if (outcome == 'CONFIRMADA') 'receipt_number': 'SERVER-ONE',
        if (outcome == 'CONFIRMADA') 'server_entity_id': 'sale-one',
        if (outcome != 'CONFIRMADA') 'error_detail': 'Stock insuficiente'}],
    });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DatabaseHelper db;
  late WalletService wallet;
  late OfflineSyncService sync;
  late _Api api;
  late _Network network;
  setUp(() async {
    sqfliteFfiInit(); databaseFactory = databaseFactoryFfi;
    final dir = await Directory.systemTemp.createTemp('fashionstore_wallet_round1_');
    await databaseFactory.setDatabasesPath(dir.path);
    DatabaseHelper.activateScope('tenant-${DateTime.now().microsecondsSinceEpoch}:user');
    db = DatabaseHelper.instance.forScope(DatabaseHelper.scope!);
    await db.saveLocalWallet(userId: 'user', saldo: 290, nonce: 4, firma: 'proof');
    await db.cacheAuthorizations([{'client_operation_id':'qa-round-wallet','channel':'WALLET',
      'authorization':'qa-contract-permit','expires_at':DateTime.now().toUtc().add(const Duration(hours:1)).toIso8601String()}]);
    api = _Api(); network = _Network();
    wallet = WalletService(api, network, StorageService());
    sync = OfflineSyncService(api, network, walletService: wallet);
    await wallet.fetchWallet();
  });
  tearDown(() async {
    sync.dispose(); wallet.dispose(); network.dispose(); api.dispose();
    DatabaseHelper.activateScope(null);
  });

  Future<String> buyOffline() async {
    final result = await wallet.payWithWallet(sucursalId: 'branch', totalAmount: 20,
      items: [{'variante_id': 'variant', 'cantidad': 1, 'precio_unitario': 20}]);
    expect(result['offline_queued'], true);
    expect(wallet.saldo, 270);
    expect(api.posts, 0);
    return result['client_operation_id'] as String;
  }

  test('sync panel counts a durable wallet order, not only cash and reservations', () async {
    await buyOffline();
    expect((await sync.getAllOperations()).single['local_status'], 'LOCAL_PENDIENTE');
    expect(await sync.refreshPendingCount(), 1);
  });

  test('sync panel button sends signed wallet order once and retains its receipt', () async {
    final id = await buyOffline();
    network.online = true;
    expect(await sync.syncBatchNow(force: true), true);
    expect(api.posts, 1);
    expect((await db.getOfflineWalletOrder(id))!['status'], 'CONFIRMADA');
    expect((await sync.getAllOperations()).single['server_receipt'], 'SERVER-ONE');
    expect(wallet.saldo, 270);
    expect(await sync.refreshPendingCount(), 0);
    await sync.syncBatchNow(force: true);
    expect(api.posts, 1);
  });

  test('reconnection automatically confirms once and updates the combined counter', () async {
    final id = await buyOffline();
    network.reconnect();
    for (var i = 0; i < 200; i++) {
      if ((await db.getOfflineWalletOrder(id))!['status'] == 'CONFIRMADA') break;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect((await db.getOfflineWalletOrder(id))!['status'], 'CONFIRMADA');
    expect(await sync.refreshPendingCount(), 0);
    network.reconnect();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(api.posts, 1);
  });

  test('401 preserves the same wallet order for explicit retry instead of another purchase', () async {
    final id = await buyOffline();
    network.online = true;
    api.failureCode = 401;
    expect(await sync.syncBatchNow(force: true), false);
    expect(sync.pendingCount, 1);
    expect(sync.lastError, 'Sesión vencida');
    expect((await db.getOfflineWalletOrder(id))!['status'], 'PENDIENTE');
    api.failureCode = null;
    expect(await sync.syncBatchNow(force: true), true);
    expect((await db.getAllWalletOrders()).single['client_operation_id'], id);
    expect(api.posts, 2);
  });

  test('stock rejection remains visible and does not debit or get retried as a new order', () async {
    final id = await buyOffline();
    api.outcome = 'COMPENSADA_POR_STOCK'; network.online = true;
    await sync.syncBatchNow(force: true);
    expect(sync.pendingCount, 0);
    expect((await sync.getAllOperations()).single['local_status'], 'COMPENSADA_POR_STOCK');
    expect((await db.getOfflineWalletOrder(id))!['error_detail'], 'Stock insuficiente');
    expect(sync.lastError, contains('Stock insuficiente'));
    expect(wallet.saldo, 290);
    await sync.syncBatchNow(force: true);
    expect(api.posts, 1);
  });

  test('switching company hides the previous wallet order and never sends it', () async {
    await buyOffline();
    DatabaseHelper.activateScope('other-${DateTime.now().microsecondsSinceEpoch}:user');
    expect(await sync.refreshPendingCount(), 0);
    expect(await sync.getAllOperations(), isEmpty);
    network.online = true;
    await sync.syncBatchNow(force: true);
    expect(api.posts, 0);
    expect((await db.getPendingOfflineWalletOrders()).length, 1);
  });

  testWidgets('offline screen counts wallet purchase and refreshes history after reconnection', (tester) async {
    Future<void> waitForScreen(Finder target) async {
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (target.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
        await tester.pump();
      }
      expect(target, findsOneWidget);
    }
    await tester.runAsync(() async {
      await buyOffline();
      await sync.refreshPendingCount();
    });
    await tester.runAsync(() async {
      await tester.pumpWidget(MultiProvider(providers: [
      ChangeNotifierProvider<ConnectivityService>.value(value: network),
      ChangeNotifierProvider<OfflineSyncService>.value(value: sync),
      ], child: const MaterialApp(home: OfflineSyncScreen())));
    });
    await waitForScreen(find.text('1 en cola local'));
    await waitForScreen(find.text('Compra con billetera'));
    await tester.runAsync(() async {
      network.reconnect();
    });
    // Wait for observable synchronization, not a machine-dependent 100ms delay.
    // Reconnection updates the already open history, without leaving the page.
    await waitForScreen(find.text('0 en cola local'));
    await waitForScreen(find.text('Sincronizada'));
    expect(api.posts, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
