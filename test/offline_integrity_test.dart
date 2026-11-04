import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:mobile/core/database/database_helper.dart';
import 'package:mobile/core/services/offline_recovery_service.dart';
import 'package:mobile/services/api_service.dart';
import 'package:mobile/services/storage_service.dart';
import 'package:path/path.dart' as path;

Map<String,dynamic> order(String id,{double amount=10}) => {
 'client_operation_id':id,'cliente_id':'user','sucursal_id':'branch','monto_total':amount,
 'items_json':jsonEncode([{'variante_id':'variant','cantidad':1,'precio_unitario':amount}]),
 'nonce_usado':1,'firma_usada':'server-proof','fecha_local':'2026-11-03T10:00:00Z',
 'status':'PENDIENTE','created_at':'2026-11-03T10:00:00Z'};
Map<String,dynamic> operation(String id)=>{
 'client_operation_id':id,'operation_type':'VENTA_CONTADO_OFFLINE','sucursal_id':'branch',
 'fecha_local':'2026-11-03T10:00:00Z','monto_total':10,'items_json':'[]','local_status':'LOCAL_PENDIENTE','created_at':'2026-11-03T10:00:00Z'};
Map<String,dynamic> confirmed(String id)=>{'client_operation_id':id,'status':'CONFIRMADA','receipt_number':'SERVER','server_entity_id':'sale'};

class _RecoveryApi extends ApiService {
 _RecoveryApi():super(StorageService());
 @override Future<ApiResponse> postAuth(String url,[Map<String,dynamic>? body,Duration? timeout,String? expectedScope]) async {
  final entries=body!['entries'] as List;
  return ApiResponse(success:true,statusCode:200,data:{'results':[
   for(var i=0;i<entries.length;i++) {'index':i,'client_operation_id':entries[i]['operation']['client_operation_id'],
    'eligible':entries[i]['operation']['cajero_id']=='user'}]});
 }
}

void main() {
 TestWidgetsFlutterBinding.ensureInitialized();
 late DatabaseHelper db;
 setUp(() async {
  sqfliteFfiInit();databaseFactory=databaseFactoryFfi;
  final dir=await Directory.systemTemp.createTemp('fashionstore_phase4_');
  await databaseFactory.setDatabasesPath(dir.path);
  final owner='tenant-${DateTime.now().microsecondsSinceEpoch}:user';DatabaseHelper.activateScope(owner);
  db=DatabaseHelper.instance.forScope(owner);
  await db.saveLocalWallet(userId:'user',saldo:20,saldoRetenido:0,nonce:1,firma:'server-proof');
 });
 tearDown(()=>DatabaseHelper.activateScope(null));
 test('wallet order and provisional debit roll back together on SQLite error',() async {
  final sqlite=await db.database;
  await sqlite.execute("CREATE TRIGGER reject_history BEFORE INSERT ON local_wallet_transactions BEGIN SELECT RAISE(ABORT,'injected write failure'); END");
  await expectLater(db.recordWalletOrder(order('one')),throwsException);
  expect(await db.getPendingOfflineWalletOrders(),isEmpty);
  expect(await db.getLocalWalletTransactions('user'),isEmpty);
  expect((await db.getLocalWallet('user'))!['saldo'],20);
 });
 test('concurrent taps cannot spend the same available balance',() async {
  final results=await Future.wait([for(final id in ['a','b']) db.recordWalletOrder(order(id,amount:15)).then((_)=>true).catchError((Object _)=>false)]);
  expect(results.where((ok)=>ok).length,1);
  expect(await db.getPendingWalletTotal('user'),15);
  expect((await db.getLocalWallet('user'))!['saldo'],20);
  expect((await db.getLocalWallet('user'))!['nonce'],1);
 });
 test('server refresh preserves durable pending total and ignores old nonce',() async {
  await db.recordWalletOrder(order('one'));
  await db.saveLocalWallet(userId:'user',saldo:30,saldoRetenido:5,nonce:3,firma:'new-proof');
  await db.saveLocalWallet(userId:'user',saldo:1000,nonce:1,firma:'stale');
  final restarted=DatabaseHelper.instance.forScope(DatabaseHelper.scope!);
  expect((await restarted.getLocalWallet('user'))!['saldo'],30);
  expect(await restarted.getPendingWalletTotal('user'),10);
 });
 test('partial wallet response cannot clear queue or change confirmed balance',() async {
  await db.recordWalletOrder(order('one'));final pending=await db.getPendingOfflineWalletOrders();
  await expectLater(db.applyWalletSyncResults('user',pending,{'results':[],'nuevo_saldo':10,'saldo_retenido':0,'nuevo_nonce':2,'nueva_firma':'new'}),throwsFormatException);
  expect(await db.getPendingWalletTotal('user'),10);
  expect((await db.getLocalWallet('user'))!['saldo'],20);
 });
 test('wallet result and authoritative snapshot apply together',() async {
  await db.recordWalletOrder(order('one'));final pending=await db.getPendingOfflineWalletOrders();
  await db.applyWalletSyncResults('user',pending,{'results':[confirmed('one')],'nuevo_saldo':10,'saldo_retenido':2,'nuevo_nonce':2,'nueva_firma':'new'});
  expect(await db.getPendingWalletTotal('user'),0);
  expect((await db.getOfflineWalletOrder('one'))!['server_receipt'],'SERVER');
  expect((await db.getLocalWallet('user'))!['saldo'],10);
  expect((await db.getLocalWallet('user'))!['saldo_retenido'],2);
  expect(await db.getLocalWalletTransactions('user'),isEmpty);
 });
 test('unvalidated legacy cache cannot fund a new payment',() async {
  await db.invalidateWallet('user');
  await expectLater(db.recordWalletOrder(order('one')),throwsStateError);
  expect((await db.getLocalWallet('user'))!['saldo'],20);
  expect(await db.getPendingOfflineWalletOrders(),isEmpty);
 });
 test('general queue rejects changed UUID and incomplete acknowledgement',() async {
  final op=operation('one');await db.insertPendingOperation(op);
  await expectLater(db.insertPendingOperation({...op,'monto_total':99}),throwsStateError);
  await expectLater(db.applySyncResults([op],{'results':[]}),throwsFormatException);
  expect(await db.getPendingCount(),1);
  await db.applySyncResults([op],{'results':[confirmed('one')]});
  await db.insertPendingOperation(op);
  expect(await db.getPendingCount(),0);
 });
 test('transient response stays pending and fixed handle cannot touch another owner',() async {
  final op=operation('one');await db.insertPendingOperation(op);
  DatabaseHelper.activateScope('other:user');
  await db.applySyncResults([op],{'results':[{'client_operation_id':'one','status':'REINTENTAR'}]});
  expect(await db.getPendingCount(),1);
  expect(await DatabaseHelper.instance.getPendingCount(),0);
 });
 test('explicit retry retains rejected parent and one successor',() async {
  final op=operation('one');await db.insertPendingOperation(op);
  await db.applySyncResults([op],{'results':[{'client_operation_id':'one','status':'CONFLICTO'}]});
  expect(await db.replaceRejectedOperation('one',operation('two')),'two');
  expect(await db.replaceRejectedOperation('one',operation('three')),'two');
  final rows=await db.getAllOperations();expect(rows.length,2);
  expect(rows.firstWhere((r)=>r['client_operation_id']=='one')['local_status'],'REEMPLAZADA');
 });
 test('explicit recovery imports only verified owner and leaves source unchanged',() async {
  final file=path.join(await getDatabasesPath(),'fashion_store.db');
  final source=await openDatabase(file,version:1,onCreate:(db,version) async {
   await db.execute('CREATE TABLE pending_operations (client_operation_id TEXT PRIMARY KEY, operation_type TEXT, sucursal_id TEXT, cajero_id TEXT, fecha_local TEXT, monto_total REAL, items_json TEXT, local_status TEXT, created_at TEXT)');
  });
  await source.insert('pending_operations',{...operation('legacy-own'),'cajero_id':'user'});
  await source.insert('pending_operations',{...operation('legacy-unknown'),'cajero_id':null});
  final before=await source.query('pending_operations');await source.close();
  final recovery=OfflineRecoveryService(_RecoveryApi());
  final preview=await recovery.preview();expect(preview,{'eligible':1,'quarantined':1});
  expect(await recovery.importVerified(),1);
  expect((await db.getPendingOperations()).map((r)=>r['client_operation_id']),['legacy-own']);
  final unchanged=await openDatabase(file,readOnly:true,singleInstance:false);
  expect(await unchanged.query('pending_operations'),before);await unchanged.close();
 });

 test('available cents are not rejected by floating point subtraction',() async {
  await db.saveLocalWallet(userId:'user',saldo:0.30,nonce:2,firma:'server-proof');
  await db.recordWalletOrder(order('fraction-one',amount:0.10));
  await db.recordWalletOrder(order('fraction-two',amount:0.20));
  expect(await db.getPendingWalletTotal('user'),closeTo(0.30,0.000001));
  await expectLater(db.recordWalletOrder(order('fraction-three',amount:0.01)),throwsStateError);
 });

}
