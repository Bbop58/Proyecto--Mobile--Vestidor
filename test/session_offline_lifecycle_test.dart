import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:uuid/uuid.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:mobile/core/database/database_helper.dart';
import 'package:mobile/core/services/connectivity_service.dart';
import 'package:mobile/core/services/offline_sync_service.dart';
import 'package:mobile/core/services/session_lifecycle_service.dart';
import 'package:mobile/core/services/offline_authorization_service.dart';
import 'package:mobile/services/api_service.dart';
import 'package:mobile/services/auth_service.dart';
import 'package:mobile/services/mobile_session_service.dart';
import 'package:mobile/services/wallet_service.dart';

import 'support/mobile_sessions.dart';

class QaConnection extends ChangeNotifier implements ConnectivityService {
  bool online = false;
  @override
  bool get isOnline => online;
  @override
  bool get wasOffline => false;
  @override
  void clearReconnectedFlag() {}
  void setOnline(bool value) {
    online = value;
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late MemorySessionStorage storage;
  late MobileSessionService sessions;
  late AuthService auth;
  late ApiService api;
  late QaConnection connection;
  late WalletService wallet;
  late OfflineSyncService sync;
  late DatabaseHelper db;
  late http.Client raw;
  late String company;
  bool unavailable = false, revoked = false, permitDenied = false;
  Completer<void>? refreshGate, refreshSent;
  int batches = 0;
  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    dir = await Directory.systemTemp.createTemp('fashionstore_sm3_lifecycle_');
    await databaseFactory.setDatabasesPath(dir.path);
    company = const Uuid().v4();
    storage = MemorySessionStorage();
    connection = QaConnection();
    unavailable = false;
    revoked = false;
    permitDenied = false;
    refreshGate = refreshSent = null;
    batches = 0;
    raw = MockClient((request) async {
      if (unavailable) throw http.ClientException('offline');
      if (request.url.path.endsWith('/logout')) return http.Response('{}', 200);
      if (refreshGate != null) {
        if (refreshSent?.isCompleted == false) refreshSent!.complete();
        await refreshGate!.future;
      }
      if (revoked) {
        return http.Response(
          '{"detail":{"code":"MOBILE_SESSION_REVOKED"}}',
          401,
        );
      }
      return http.Response(jsonEncode(response(company: company)), 200);
    });
    sessions = MobileSessionService(storage, client: raw);
    api = ApiService(
      storage,
      sessions: sessions,
      client: MockClient((request) async {
        if (request.url.path.endsWith('/authorizations')) {
          return permitDenied
              ? http.Response('{}', 403)
              : http.Response('{"grants":[]}', 200);
        }
        if (request.url.path.endsWith('/sync/batch')) {
          batches++;
          final rows = jsonDecode(request.body)['operations'] as List;
          return http.Response(
            jsonEncode({
              'results': rows
                  .map(
                    (r) => {
                      'client_operation_id': r['client_operation_id'],
                      'status': 'CONFIRMADA',
                      'receipt_number': 'SM3-ONE',
                      'server_entity_id': 'qa-sale',
                    },
                  )
                  .toList(),
            }),
            200,
          );
        }
        return http.Response('[]', 200);
      }),
    );
    auth = AuthService(api, storage);
    await sessions.establish(response(company: company));
    db = DatabaseHelper.instance.forScope(DatabaseHelper.scope!);
    await db.saveLocalWallet(
      userId: userA,
      saldo: 100,
      nonce: 1,
      firma: 'synthetic-proof',
    );
    wallet = WalletService(api, connection, storage);
    sync = OfflineSyncService(api, connection, walletService: wallet);
    await wallet.fetchWallet();
  });
  tearDown(() async {
    sync.dispose();
    wallet.dispose();
    auth.dispose();
    api.dispose();
    sessions.dispose();
    raw.close();
    connection.dispose();
    DatabaseHelper.activateScope(null);
  });
  Future<void> permit(String channel, {bool expired = false}) =>
      db.cacheAuthorizations([
        {
          'client_operation_id': 'qa-${channel.toLowerCase()}',
          'channel': channel,
          'authorization': 'synthetic-authorization',
          'expires_at': DateTime.now()
              .toUtc()
              .add(Duration(hours: expired ? -1 : 1))
              .toIso8601String(),
        },
      ]);

  for (final expired in [false, true]) {
    test(
      'new offline wallet purchase requires a valid permit (expired=$expired)',
      () async {
        if (expired) await permit('WALLET', expired: true);
        await expectLater(
          wallet.payWithWallet(
            sucursalId: 'branch',
            items: [
              {'variante_id': 'v', 'cantidad': 1, 'precio_unitario': 20},
            ],
            totalAmount: 20,
          ),
          throwsStateError,
        );
        expect(await db.getPendingOfflineWalletOrders(), isEmpty);
        expect(wallet.saldo, 100);
      },
    );
  }
  test('expired SYNC permit blocks new reservation and preserves existing pending work', () async {
    await db.insertPendingOperation({
      'client_operation_id': 'previous',
      'operation_type': 'RESERVA_OFFLINE',
      'sucursal_id': 'branch',
      'cliente_id': userA,
      'fecha_local': DateTime.now().toUtc().toIso8601String(),
      'monto_total': 10,
      'items_json': '[]',
      'local_status': 'LOCAL_PENDIENTE',
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
    await permit('SYNC', expired: true);
    await expectLater(
      sync.saveOfflineReservation(
        sucursalId: 'branch',
        items: [],
        montoTotal: 20,
      ),
      throwsStateError,
    );
    expect(
      (await db.getPendingOperations()).single['client_operation_id'],
      'previous',
    );
  });
  test('known restricted account cannot create new offline orders despite a cached permit', () async {
    final data = response(company: company);
    (data['user'] as Map)['service_restricted'] = true;
    await sessions.establish(data);
    await wallet.fetchWallet();
    await permit('WALLET');
    await expectLater(
      wallet.payWithWallet(sucursalId: 'branch', items: [], totalAmount: 20),
      throwsStateError,
    );
    expect(await db.getPendingOfflineWalletOrders(), isEmpty);
  });
  test('startup online synchronizes restored pending work without a new network event', () async {
    await permit('SYNC');
    final id = await sync.saveOfflineReservation(
      sucursalId: 'branch',
      items: [],
      montoTotal: 20,
    );
    await auth.logout();
    connection.online = true;
    final lifecycle = SessionLifecycleService(
      api,
      connection,
      onReady: () async {
        await sync.syncBatchNow();
      },
    );
    lifecycle.start();
    await sessions.establish(response(company: company));
    for (var n = 0; n < 100 && batches == 0; n++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(batches, 1);
    expect((await db.getAllOperations()).single['client_operation_id'], id);
    lifecycle.dispose();
  });
  test('network availability alone never sends a queue before session revalidation', () async {
    await permit('SYNC');
    await sync.saveOfflineReservation(
      sucursalId: 'branch',
      items: [],
      montoTotal: 20,
    );
    unavailable = true;
    connection.online = true;
    expect(await sync.syncBatchNow(force: true), false);
    expect(batches, 0);
    expect(await db.getPendingCount(), 1);
  });
  test(
    'definitively revoked session pauses sync without deleting its SQLite rows',
    () async {
      await permit('SYNC');
      final id = await sync.saveOfflineReservation(
        sucursalId: 'branch',
        items: [],
        montoTotal: 20,
      );
      revoked = true;
      connection.online = true;
      expect(await sync.syncBatchNow(force: true), false);
      expect(batches, 0);
      expect(auth.isAuthenticated, false);
      expect(DatabaseHelper.scope, isNull);
      expect(
        (await db.getPendingOperations()).single['client_operation_id'],
        id,
      );
      expect(storage.saved!.active, isNull);
    },
  );
  test('a late resume never flushes the next account or reassigns the previous queue', () async {
    await permit('SYNC');
    final id = await sync.saveOfflineReservation(
      sucursalId: 'branch',
      items: [],
      montoTotal: 20,
    );
    refreshGate = Completer<void>();
    refreshSent = Completer<void>();
    connection.online = true;
    var callbacks = 0;
    final lifecycle = SessionLifecycleService(
      api,
      connection,
      onReady: () async {
        callbacks++;
        await sync.syncBatchNow();
      },
    );
    final first = lifecycle.resume();
    final shared = lifecycle.resume();
    await refreshSent!.future;
    await auth.logout();
    await sessions.establish(
      response(sid: sessionB, user: userB, company: companyB),
    );
    refreshGate!.complete();
    await Future.wait([first, shared]);
    expect(callbacks, 0);
    expect(batches, 0);
    expect(auth.currentUser!.id, userB);
    expect((await db.getPendingOperations()).single['client_operation_id'], id);
    expect(
      await DatabaseHelper.instance
          .forScope(DatabaseHelper.scope!)
          .getPendingCount(),
      0,
    );
    lifecycle.dispose();
  });
  test('denied permits are removed durably while existing queues and other channels remain', () async {
    await permit('SYNC');
    final id = await sync.saveOfflineReservation(
      sucursalId: 'branch',
      items: [],
      montoTotal: 20,
    );
    await db.cacheAuthorizations([
      {
        'client_operation_id': 'next-sync',
        'channel': 'SYNC',
        'authorization': 'unused',
        'expires_at': DateTime.now()
            .toUtc()
            .add(const Duration(hours: 1))
            .toIso8601String(),
      },
    ]);
    await permit('WALLET');
    permitDenied = true;
    await OfflineAuthorizationService(api).prefetch('SYNC');
    expect(await db.takeAuthorization('SYNC'), isNull);
    expect(await db.takeAuthorization('WALLET'), isNotNull);
    expect((await db.getPendingOperations()).single['client_operation_id'], id);
  });
  test('logout offline is only revoked on reconnect, never used to activate a business identity', () async {
    unavailable = true;
    await auth.logout();
    await sessions.flushPendingRevocations();
    expect(storage.saved!.active, isNull);
    expect(storage.saved!.pendingRevocations, isNotEmpty);
    connection.online = true;
    unavailable = false;
    var callbacks = 0;
    final lifecycle = SessionLifecycleService(
      api,
      connection,
      onReady: () async {
        callbacks++;
      },
    );
    await lifecycle.resume();
    expect(callbacks, 0);
    expect(batches, 0);
    expect(auth.isAuthenticated, false);
    expect(storage.saved!.pendingRevocations, isEmpty);
    lifecycle.dispose();
  });
  test('manual revalidation after a transient failure resumes queues in the same session', () async {
    connection.online = true;
    var callbacks = 0;
    final lifecycle = SessionLifecycleService(
      api,
      connection,
      onReady: () async {
        callbacks++;
      },
    );
    lifecycle.start();
    await lifecycle.resume(revalidate: false);
    expect(callbacks, 1);
    unavailable = true;
    await lifecycle.resume();
    expect(callbacks, 1);
    unavailable = false;
    await auth.revalidateSession();
    for (var n = 0; n < 100 && callbacks < 2; n++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(callbacks, 2);
    lifecycle.dispose();
  });
  test('Wi-Fi without reachable backend cannot create unlicensed wallet or reservation work', () async {
    connection.online = true;
    unavailable = true;
    await expectLater(
      wallet.payWithWallet(sucursalId: 'branch', items: [], totalAmount: 20),
      throwsStateError,
    );
    await expectLater(
      sync.saveOfflineReservation(
        sucursalId: 'branch',
        items: [],
        montoTotal: 20,
      ),
      throwsStateError,
    );
    expect(await db.getPendingOfflineWalletOrders(), isEmpty);
    expect(await db.getPendingOperations(), isEmpty);
  });
}
