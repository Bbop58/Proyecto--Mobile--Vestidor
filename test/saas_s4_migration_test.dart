import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:mobile/core/database/database_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('v6 upgrade preserves pending work and consumes scoped permits once', () async {
    sqfliteFfiInit();databaseFactory=databaseFactoryFfi;
    final dir=await Directory.systemTemp.createTemp('fashionstore_saas_s4_');
    await databaseFactory.setDatabasesPath(dir.path);
    final owner='s4-${DateTime.now().microsecondsSinceEpoch}:user';
    final file=path.join(dir.path,'fashion_store_v2_${owner.replaceAll(':','_')}.db');
    final old=await openDatabase(file,version:6,onCreate:(db,v) async {
      await db.execute('CREATE TABLE pending_operations (client_operation_id TEXT PRIMARY KEY, local_status TEXT)');
      await db.execute('CREATE TABLE offline_wallet_orders (client_operation_id TEXT PRIMARY KEY, status TEXT)');
      await db.execute('CREATE TABLE local_wallet (user_id TEXT PRIMARY KEY, saldo REAL, nonce INTEGER, firma TEXT)');
      await db.execute('CREATE TABLE favorite_mutations (product_id TEXT PRIMARY KEY, desired INTEGER)');
    });
    await old.insert('pending_operations',{'client_operation_id':'cash-old','local_status':'LOCAL_PENDIENTE'});
    await old.insert('offline_wallet_orders',{'client_operation_id':'wallet-old','status':'PENDIENTE'});
    await old.insert('local_wallet',{'user_id':'user','saldo':290,'nonce':4,'firma':'old-server-proof'});
    await old.insert('favorite_mutations',{'product_id':'favorite-old','desired':1});await old.close();
    DatabaseHelper.activateScope(owner);final helper=DatabaseHelper.instance.forScope(owner);
    final db=await helper.database;expect(await db.getVersion(),8);
    expect((await db.query('local_wallet')).single['saldo'],290);
    expect((await db.query('local_wallet')).single['nonce'],4);
    expect((await db.query('favorite_mutations')).single['product_id'],'favorite-old');
    expect((await db.query('pending_operations')).single['offline_authorization'],isNull);
    expect((await db.query('offline_wallet_orders')).single['client_operation_id'],'wallet-old');
    await helper.cacheAuthorizations([{'client_operation_id':'permit-one','channel':'WALLET',
      'authorization':'opaque-server-proof','expires_at':DateTime.now().toUtc().add(const Duration(hours:1)).toIso8601String()}]);
    final results=await Future.wait([helper.takeAuthorization('WALLET'),helper.takeAuthorization('WALLET')]);
    expect(results.whereType<Map>().length,1);
    expect((await db.query('offline_wallet_orders')).length,1);
    DatabaseHelper.activateScope(null);
  });
}
