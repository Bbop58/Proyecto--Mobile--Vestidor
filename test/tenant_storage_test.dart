import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:mobile/core/database/database_helper.dart';
import 'package:mobile/models/user.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('SQLite preserves queues per company and account including an in-flight owner', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final directory = await Directory.systemTemp.createTemp(
      'fashionstore_phase1_',
    );
    await databaseFactory.setDatabasesPath(directory.path);
    final helper = DatabaseHelper.instance;
    DatabaseHelper.activateScope('company-a:user-a');
    final owned = helper.forScope('company-a:user-a');
    Map<String, dynamic> operation(String id) => {
      'client_operation_id': id,
      'operation_type': 'VENTA_CONTADO_OFFLINE',
      'sucursal_id': 'branch-a',
      'fecha_local': '2026-11-03T00:00:00Z',
      'monto_total': 10,
      'items_json': '[]',
      'local_status': 'LOCAL_PENDIENTE',
      'created_at': '2026-11-03',
    };
    await helper.insertPendingOperation(operation('first'));
    DatabaseHelper.activateScope('company-b:user-b');
    expect(await helper.getPendingCount(), 0);
    await owned.insertPendingOperation(operation('in-flight-a'));
    expect(await helper.getPendingCount(), 0);
    DatabaseHelper.activateScope('company-a:user-a');
    expect(await helper.getPendingCount(), 2);
    DatabaseHelper.activateScope(null);
    expect(await helper.getPendingCount(), 0);
    await expectLater(
      helper.insertPendingOperation(operation('anonymous')),
      throwsStateError,
    );
    // Named disposable test directory is retained; no application database is removed.
  });

  test(
    'user profile carries immutable company through serialization and edits',
    () {
      final user = User.fromJson({
        'id': 'a',
        'tenant_id': 'company-a',
        'full_name': 'Customer A',
      });
      expect(user.tenantId, 'company-a');
      expect(
        user.copyWith(fullName: 'Edited').toJson()['tenant_id'],
        'company-a',
      );
    },
  );

  test('wallet v3 upgrade preserves pending orders and adds coupon and held balance', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final directory = await Directory.systemTemp.createTemp('fashionstore_phase3_upgrade_');
    await databaseFactory.setDatabasesPath(directory.path);
    final old = await openDatabase('${directory.path}/fashion_store_v2_phase3_user.db', version: 3,
      onCreate: (db, version) async {
        await db.execute('CREATE TABLE local_wallet (user_id TEXT PRIMARY KEY, saldo REAL, nonce INTEGER, firma TEXT, moneda TEXT, updated_at TEXT)');
        await db.execute('CREATE TABLE offline_wallet_orders (client_operation_id TEXT PRIMARY KEY, cliente_id TEXT, sucursal_id TEXT, monto_total REAL, nonce_usado INTEGER, firma_usada TEXT, items_json TEXT, fecha_local TEXT, status TEXT, server_receipt TEXT, error_detail TEXT, created_at TEXT)');
        await db.insert('local_wallet', {'user_id': 'user', 'saldo': 20, 'nonce': 1, 'firma': 'sealed'});
        await db.insert('offline_wallet_orders', {'client_operation_id': 'legacy', 'status': 'PENDIENTE'});
      });
    await old.close();
    final scoped = DatabaseHelper.instance.forScope('phase3:user');
    final wallet = await scoped.getLocalWallet('user');
    expect(wallet?['saldo'], 20);
    expect(wallet?['saldo_retenido'], 0);
    expect((await scoped.getOfflineWalletOrder('legacy'))?['status'], 'PENDIENTE');
    await scoped.saveLocalWallet(userId: 'user', saldo: 20, saldoRetenido: 5, nonce: 1, firma: 'sealed');
    expect((await scoped.getLocalWallet('user'))?['saldo_retenido'], 5);
    await scoped.insertOfflineWalletOrder({'client_operation_id': 'coupon-order', 'codigo_cupon': 'REAL',
      'status': 'PENDIENTE', 'sucursal_id': 'branch', 'monto_total': 10, 'items_json': '[]',
      'fecha_local': '2026-11-03', 'created_at': '2026-11-03'});
    expect((await scoped.getOfflineWalletOrder('coupon-order'))?['codigo_cupon'], 'REAL');
  });
}
