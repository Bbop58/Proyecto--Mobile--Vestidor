import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile/core/database/database_helper.dart';
import 'package:mobile/core/services/offline_sync_service.dart';
import 'package:mobile/models/mobile_session.dart';
import 'package:mobile/services/api_service.dart';
import 'package:mobile/services/auth_service.dart';
import 'package:mobile/services/favorite_service.dart';
import 'package:mobile/services/mobile_session_service.dart';
import 'package:mobile/services/storage_service.dart';
import 'package:mobile/services/wallet_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'channel_contracts_test.dart' show product;
import 'session_offline_lifecycle_test.dart' show QaConnection;
import 'support/mobile_sessions.dart';

// Synthetic credentials only. This file-backed double tests process boundaries,
// not Android Keystore; the actual SQLite database is never mocked.
class _FileStorage extends StorageService {
  final File file;
  _FileStorage(this.file);
  @override
  Future<SessionEnvelope?> readSessionEnvelope() async => await file.exists()
      ? SessionEnvelope.fromJson(
          jsonDecode(await file.readAsString()) as Map<String, dynamic>,
        )
      : null;
  @override
  Future<void> writeSessionEnvelope(SessionEnvelope value) async {
    await file.writeAsString(jsonEncode(value.toJson()), flush: true);
  }

  @override
  Future<Map<String, String>?> readLegacySession() async => null;
  @override
  Future<void> clearLegacySession() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const stage = String.fromEnvironment('SM3_STAGE', defaultValue: 'both');
  const configuredPath = String.fromEnvironment('SM3_QA_PATH');
  test(
    'real SQLite survives process boundary and reconciles the original operations ($stage)',
    () async {
      expect(['both', 'write', 'read'].contains(stage), true);
      final root = configuredPath.isEmpty
          ? await Directory.systemTemp.createTemp('fashionstore_sm3_restart_')
          : Directory(configuredPath);
      final allowed = Directory.systemTemp.absolute.path
          .replaceAll('\\', '/')
          .toLowerCase();
      expect(
        root.absolute.path
            .replaceAll('\\', '/')
            .toLowerCase()
            .startsWith('$allowed/fashionstore_sm3_restart_'),
        true,
      );
      await root.create(recursive: true);
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      await databaseFactory.setDatabasesPath(root.path);
      final storage = _FileStorage(File('${root.path}/synthetic-session.json'));
      final expectedFile = File('${root.path}/expected.json');
      final ledgerFile = File('${root.path}/ledger.json');
      var online = false, verified = false, lost = false;
      final ledger = <String, Map<String, dynamic>>{};
      if (await ledgerFile.exists()) {
        final saved = jsonDecode(await ledgerFile.readAsString()) as Map;
        for (final entry in saved.entries) {
          ledger[entry.key.toString()] = Map<String, dynamic>.from(
            entry.value as Map,
          );
        }
      }
      final raw = MockClient((r) async {
        if (!online) throw http.ClientException('offline');
        if (r.url.path.endsWith('/logout')) return http.Response('{}', 200);
        verified = true;
        return http.Response(jsonEncode(response()), 200);
      });
      final sessions = MobileSessionService(storage, client: raw);
      final api = ApiService(
        storage,
        sessions: sessions,
        client: MockClient((r) async {
          expect(
            verified,
            true,
            reason: 'Business transport requires server-revalidated identity',
          );
          final body = r.body.isEmpty ? null : jsonDecode(r.body);
          if (r.url.path.endsWith('/authorizations')) {
            return http.Response('{"grants":[]}', 200);
          }
          if (r.url.path.endsWith('/wallet/sync-offline-orders')) {
            final row = (body['orders'] as List).single as Map;
            final id = row['client_operation_id'].toString();
            final previous = ledger['wallet:$id'];
            if (previous != null) expect(jsonEncode(row), jsonEncode(previous));
            ledger['wallet:$id'] = Map<String, dynamic>.from(row);
            await ledgerFile.writeAsString(jsonEncode(ledger), flush: true);
            if (!lost) {
              lost = true;
              return http.Response('{}', 504);
            }
            return http.Response(
              jsonEncode({
                'nuevo_saldo': 80,
                'saldo_retenido': 0,
                'nuevo_nonce': 2,
                'nueva_firma': 'synthetic-server-proof-2',
                'results': [
                  {
                    'client_operation_id': id,
                    'status': 'CONFIRMADA',
                    'receipt_number': 'SM3-WALLET',
                    'server_entity_id': 'qa-wallet-sale',
                  },
                ],
              }),
              200,
            );
          }
          if (r.url.path.endsWith('/sync/batch')) {
            final row = (body['operations'] as List).single as Map;
            final id = row['client_operation_id'].toString();
            ledger['reservation:$id'] = Map<String, dynamic>.from(row);
            await ledgerFile.writeAsString(jsonEncode(ledger), flush: true);
            return http.Response(
              jsonEncode({
                'results': [
                  {
                    'client_operation_id': id,
                    'status': 'CONFIRMADA',
                    'receipt_number': 'SM3-RESERVATION',
                    'server_entity_id': 'qa-reservation',
                  },
                ],
              }),
              200,
            );
          }
          if (r.url.path.endsWith('/favorites')) {
            if (r.method == 'POST') {
              ledger['favorite'] = Map<String, dynamic>.from(body as Map);
              return http.Response('{}', 201);
            }
            return http.Response(
              jsonEncode([
                {'producto': product().toJson()},
              ]),
              200,
            );
          }
          if (r.url.path.endsWith('/wallet/me')) {
            return http.Response(
              jsonEncode({
                'id': 'qa-wallet',
                'user_id': userA,
                'saldo_actual': 80,
                'saldo_retenido': 0,
                'nonce_secuencia': 2,
                'firma_balance': 'synthetic-server-proof-2',
                'moneda': 'BOB',
              }),
              200,
            );
          }
          return http.Response('[]', 200);
        }),
      );
      final auth = AuthService(api, storage), connection = QaConnection();
      final wallet = WalletService(api, connection, storage);
      final sync = OfflineSyncService(api, connection, walletService: wallet);
      final favorites = FavoriteService(api, connection, storage);
      if (stage != 'read') {
        await sessions.establish(response());
      } else {
        await auth.initialize();
      }
      expect(auth.isAuthenticated, true);
      expect(DatabaseHelper.scope, '$companyA:$userA');
      final db = DatabaseHelper.instance.forScope(DatabaseHelper.scope!);
      if (stage != 'read') {
        await db.saveLocalWallet(
          userId: userA,
          saldo: 100,
          nonce: 1,
          firma: 'synthetic-proof-1',
        );
        await db.cacheProducts([
          {
            'id': 'qa-product',
            'nombre': 'QA',
            'categoria': 'QA',
            'precio_base': 20,
            'imagen_url': '',
            'variantes_json': '[]',
          },
        ]);
        await db.cacheBranches([
          {
            'id': 'qa-branch',
            'nombre': 'QA branch',
            'direccion': 'QA',
            'activa': true,
          },
        ]);
        await db.cacheAuthorizations([
          for (final channel in ['SYNC', 'WALLET'])
            {
              'client_operation_id': 'sm3-$channel',
              'channel': channel,
              'authorization': 'synthetic-$channel-permit',
              'expires_at': DateTime.now()
                  .toUtc()
                  .add(const Duration(hours: 1))
                  .toIso8601String(),
            },
        ]);
        await wallet.fetchWallet();
        await favorites.toggleFavorite(product());
        final paid = await wallet.payWithWallet(
          sucursalId: 'qa-branch',
          items: [
            {'variante_id': 'qa-variant', 'cantidad': 1, 'precio_unitario': 20},
          ],
          totalAmount: 20,
        );
        final reserved = await sync.saveOfflineReservation(
          sucursalId: 'qa-branch',
          items: [
            {'variante_id': 'qa-variant', 'cantidad': 1, 'precio_unitario': 20},
          ],
          montoTotal: 20,
        );
        await expectedFile.writeAsString(
          jsonEncode({
            'wallet': paid['client_operation_id'],
            'reservation': reserved,
            'wallet_row': (await db.getPendingOfflineWalletOrders()).single,
            'reservation_row': (await db.getPendingOperations()).single,
          }),
          flush: true,
        );
      }
      if (stage != 'write') {
        final expected = jsonDecode(await expectedFile.readAsString()) as Map;
        expect(
          jsonEncode((await db.getPendingOfflineWalletOrders()).single),
          jsonEncode(expected['wallet_row']),
        );
        expect(
          jsonEncode((await db.getPendingOperations()).single),
          jsonEncode(expected['reservation_row']),
        );
        expect((await db.getCachedProducts()).single['id'], 'qa-product');
        expect((await db.getCachedBranches()).single['id'], 'qa-branch');
        await wallet.fetchWallet();
        expect(wallet.saldo, 80);
        expect(wallet.wallet!.nonceSecuencia, 1);
        await favorites.loadLocalFavorites();
        expect(favorites.count, 1);
        expect(await sync.refreshPendingCount(), 2);
        await expectLater(
          wallet.payWithWallet(
            sucursalId: 'qa-branch',
            items: [],
            totalAmount: 10,
          ),
          throwsStateError,
        );
        expect((await db.getPendingOfflineWalletOrders()).length, 1);
        online = true;
        connection.online = true;
        expect(
          await sync.syncBatchNow(force: true),
          false,
          reason: 'First wallet response is lost after simulated commit',
        );
        expect(
          (await db.getPendingOfflineWalletOrders())
              .single['client_operation_id'],
          expected['wallet'],
        );
        expect(await sync.syncBatchNow(force: true), true);
        await favorites.fetchFavorites();
        await sync.refreshPendingCount();
        expect(sync.pendingCount, 0);
        expect(wallet.saldo, 80);
        expect(wallet.wallet!.nonceSecuencia, 2);
        expect(
          (await db.getAllWalletOrders()).single['server_receipt'],
          'SM3-WALLET',
        );
        expect(
          (await db.getAllOperations()).single['server_receipt'],
          'SM3-RESERVATION',
        );
        expect(await db.pendingFavoriteChanges(userA), isEmpty);
        expect(ledger.keys.where((k) => k.startsWith('wallet:')).length, 1);
        expect(
          ledger.keys.where((k) => k.startsWith('reservation:')).length,
          1,
        );
        final sent = ledger['wallet:${expected['wallet']}']!;
        expect(sent['firma_cliente'], 'synthetic-proof-1');
        expect(sent['nonce'], 1);
        expect(sent['offline_authorization'], 'synthetic-WALLET-permit');
        await ledgerFile.writeAsString(jsonEncode(ledger), flush: true);
      }
      sync.dispose();
      wallet.dispose();
      favorites.dispose();
      auth.dispose();
      api.dispose();
      sessions.dispose();
      raw.close();
      connection.dispose();
      DatabaseHelper.activateScope(null);
      await (await db.database).close();
    },
  );
}
