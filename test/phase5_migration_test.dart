import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:mobile/core/database/database_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'SQLite v5 upgrade preserves validated balance, pending orders and catalog',
    () async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final dir = await Directory.systemTemp.createTemp(
        'fashionstore_v5_upgrade_',
      );
      await databaseFactory.setDatabasesPath(dir.path);
      const owner = 'upgrade-phase5:user';
      final file = path.join(
        dir.path,
        'fashion_store_v2_upgrade-phase5_user.db',
      );
      final old = await openDatabase(
        file,
        version: 5,
        onCreate: (db, v) async {
          await db.execute(
            'CREATE TABLE local_wallet (user_id TEXT PRIMARY KEY, saldo REAL, saldo_retenido REAL, nonce INTEGER, firma TEXT, server_validated INTEGER)',
          );
          await db.execute(
            'CREATE TABLE pending_operations (client_operation_id TEXT PRIMARY KEY, local_status TEXT)',
          );
          await db.execute(
            'CREATE TABLE offline_wallet_orders (client_operation_id TEXT PRIMARY KEY, status TEXT)',
          );
          await db.execute(
            'CREATE TABLE cached_products (id TEXT PRIMARY KEY,nombre TEXT,precio_base REAL)',
          );
        },
      );
      await old.insert('local_wallet', {
        'user_id': 'user',
        'saldo': 20,
        'saldo_retenido': 5,
        'nonce': 7,
        'firma': 'verified',
        'server_validated': 1,
      });
      await old.insert('pending_operations', {
        'client_operation_id': 'pending-sale',
        'local_status': 'LOCAL_PENDIENTE',
      });
      await old.insert('offline_wallet_orders', {
        'client_operation_id': 'pending-wallet',
        'status': 'PENDIENTE',
      });
      await old.insert('cached_products', {
        'id': 'product',
        'nombre': 'Camisa',
        'precio_base': 10,
      });
      await old.close();
      DatabaseHelper.activateScope(owner);
      final helper = DatabaseHelper.instance.forScope(owner);
      final db = await helper.database;
      expect(await db.getVersion(), 6);
      expect((await helper.getLocalWallet('user'))!['server_validated'], 1);
      expect((await helper.getLocalWallet('user'))!['saldo'], 20);
      expect((await helper.getLocalWallet('user'))!['nonce'], 7);
      expect(await helper.getPendingCount(), 1);
      expect(
        (await db.query('offline_wallet_orders')).single['client_operation_id'],
        'pending-wallet',
      );
      expect((await helper.getCachedProducts()).single['nombre'], 'Camisa');
      expect(await helper.pendingFavoriteChanges('user'), isEmpty);
      expect(
        (await db.rawQuery('PRAGMA table_info(cached_products)'))
            .map((r) => r['name']),
        containsAll(['categoria_id', 'temporada']),
      );
      DatabaseHelper.activateScope(null);
    },
  );
}
