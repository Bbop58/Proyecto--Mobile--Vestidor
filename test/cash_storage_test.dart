import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:mobile/core/database/database_helper.dart';
import 'package:mobile/models/cash_snapshot.dart';

String grant(String owner,String id,{String kind='VENTA_CONTADO_OFFLINE'}) {
  final p=owner.split(':');
  String enc(Object x)=>base64Url.encode(utf8.encode(jsonEncode(x))).replaceAll('=','');
  return '${enc({'alg':'HS256'})}.${enc({'purpose':'OFFLINE_ENTITLEMENT','tenant_id':p[0],
    'actor_id':p[1],'operation_id':id,'channel':'SYNC','kinds':[kind],
    'exp':DateTime.now().toUtc().add(const Duration(hours:2)).millisecondsSinceEpoch~/1000})}.signature';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    sqfliteFfiInit(); databaseFactory=databaseFactoryFfi;
    final dir=await Directory.systemTemp.createTemp('cash-storage-');
    await databaseFactory.setDatabasesPath(dir.path);
  });
  tearDownAll(() {DatabaseHelper.activateScope(null);});

  test('one request saves once, consumes one grant, and preserves wallet', () async {
    final owner='company:person-${DateTime.now().microsecondsSinceEpoch}';
    DatabaseHelper.activateScope(owner);
    final helper=DatabaseHelper.instance.forScope(owner);
    final now=DateTime.now().toUtc();
    await helper.saveCashSnapshot(CashSnapshot(owner:owner,branchId:'branch',preparedAt:now,
      validUntil:now.add(const Duration(hours:1)),products:[],availability:[
        {'variante_id':'variant','stock_disponible':2,'precio':20.0}
      ]).toRow());
    await helper.saveLocalWallet(userId:'person',saldo:90,nonce:2,firma:'signed');
    await helper.cacheAuthorizations([{'client_operation_id':'op-1','channel':'SYNC',
      'authorization':grant(owner,'op-1'),'expires_at':now.add(const Duration(hours:2)).toIso8601String()}]);
    Future<String> save(List<Map<String,dynamic>> items)=>helper.saveAuthorizedCashOperation(
      owner:owner,branchId:'branch',cashierId:owner.split(':')[1],localRequestId:'tap-1',
      items:items,totalCents:2000,receivedCents:3000);
    final items=[{'variante_id':'variant','cantidad':1,'precio_unitario':20.0}];
    expect(await save(items),'op-1');
    expect(await save(items),'op-1');
    await expectLater(save([{'variante_id':'variant','cantidad':2,'precio_unitario':20.0}]),throwsStateError);
    final db=await helper.database;
    expect((await db.query('pending_operations')).length,1);
    expect((await db.query('offline_authorizations')).length,0);
    final wallet=await helper.getLocalWallet('person');
    expect(wallet?['saldo'],90); expect(wallet?['nonce'],2);
  });

  test('stock and invalid grants fail without consuming a permit or writing money', () async {
    final owner='company:person-${DateTime.now().microsecondsSinceEpoch}';
    DatabaseHelper.activateScope(owner);
    final helper=DatabaseHelper.instance.forScope(owner);
    final now=DateTime.now().toUtc();
    await helper.saveCashSnapshot(CashSnapshot(owner:owner,branchId:'branch',preparedAt:now,
      validUntil:now.add(const Duration(hours:1)),products:[],availability:[
        {'variante_id':'variant','stock_disponible':1,'precio':20.0}
      ]).toRow());
    await helper.cacheAuthorizations([{'client_operation_id':'bad-1','channel':'SYNC',
      'authorization':grant(owner,'bad-1',kind:'RESERVA_OFFLINE'),
      'expires_at':now.add(const Duration(hours:2)).toIso8601String()}]);
    Future<String> save(String request,int qty)=>helper.saveAuthorizedCashOperation(
      owner:owner,branchId:'branch',cashierId:owner.split(':')[1],localRequestId:request,
      items:[{'variante_id':'variant','cantidad':qty,'precio_unitario':20.0}],
      totalCents:2000*qty,receivedCents:3000*qty);
    await expectLater(save('first',1),throwsStateError);
    final db=await helper.database;
    expect((await db.query('offline_authorizations')).length,1);
    expect(await db.query('pending_operations'),isEmpty);
    await helper.cacheAuthorizations([{'client_operation_id':'good-1','channel':'SYNC',
      'authorization':grant(owner,'good-1'),
      'expires_at':now.add(const Duration(hours:2)).toIso8601String()}]);
    await db.execute("CREATE TRIGGER reject_cash BEFORE INSERT ON pending_operations BEGIN SELECT RAISE(ABORT, 'disk simulation'); END");
    await expectLater(save('first',1),throwsException);
    expect((await db.query('offline_authorizations',where:'client_operation_id=?',whereArgs:['good-1'])).length,1);
    expect(await db.query('pending_operations'),isEmpty);
    await db.execute('DROP TRIGGER reject_cash');
    expect(await save('first',1),'good-1');
    await expectLater(save('second',1),throwsStateError);
    expect((await db.query('pending_operations')).length,1);
    expect((await db.query('offline_authorizations',where:'client_operation_id=?',whereArgs:['bad-1'])).length,1);
  });
}
