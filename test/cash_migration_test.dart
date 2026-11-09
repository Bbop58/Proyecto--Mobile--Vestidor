import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:mobile/core/database/database_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('v7 to v8 preserves pending money and adds cash storage', () async {
    sqfliteFfiInit(); databaseFactory = databaseFactoryFfi;
    final dir = await Directory.systemTemp.createTemp('cash-migration-');
    await databaseFactory.setDatabasesPath(dir.path);
    final owner = 'cash_${DateTime.now().microsecondsSinceEpoch}';
    final file = path.join(dir.path, 'fashion_store_v2_$owner.db');
    final old = await openDatabase(file, version: 7, onCreate: (db, _) async {
      await db.execute('CREATE TABLE pending_operations (client_operation_id TEXT PRIMARY KEY, local_status TEXT)');
      await db.execute('CREATE TABLE offline_wallet_orders (client_operation_id TEXT PRIMARY KEY, status TEXT)');
      await db.execute('CREATE TABLE local_wallet (user_id TEXT PRIMARY KEY, saldo REAL, nonce INTEGER)');
      await db.execute('CREATE TABLE offline_authorizations (client_operation_id TEXT PRIMARY KEY, channel TEXT, authorization TEXT, expires_at TEXT)');
    });
    await old.insert('pending_operations', {'client_operation_id':'sale-old','local_status':'LOCAL_PENDIENTE'});
    await old.insert('offline_wallet_orders', {'client_operation_id':'wallet-old','status':'PENDIENTE'});
    await old.insert('local_wallet', {'user_id':'person','saldo':290,'nonce':4});
    await old.close();
    final db = await DatabaseHelper.instance.forScope(owner).database;
    expect(await db.getVersion(), 8);
    expect((await db.rawQuery("SELECT name FROM sqlite_master WHERE name='cash_snapshots'")).length, 1);
    expect((await db.rawQuery('PRAGMA table_info(pending_operations)')).any((c)=>c['name']=='local_request_id'), isTrue);
    expect((await db.query('pending_operations')).single['client_operation_id'], 'sale-old');
    expect((await db.query('offline_wallet_orders')).single['client_operation_id'], 'wallet-old');
    expect((await db.query('local_wallet')).single['saldo'], 290);
    expect((await db.query('local_wallet')).single['nonce'], 4);
  });
}
