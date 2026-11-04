import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:mobile/core/database/database_helper.dart';
import 'package:mobile/core/services/connectivity_service.dart';
import 'package:mobile/core/services/offline_sync_service.dart';
import 'package:mobile/services/api_service.dart';
import 'package:mobile/services/storage_service.dart';

class _Connectivity extends ChangeNotifier implements ConnectivityService {
 @override bool get isOnline=>true;
 @override bool get wasOffline=>false;
 @override void clearReconnectedFlag() {}
}
class _Api extends ApiService {
 _Api():super(StorageService());
 int posts=0;
 final response=Completer<ApiResponse>();
 @override Future<ApiResponse> postAuth(String url,[Map<String,dynamic>? body,Duration? timeout,String? expectedScope]) { posts++;return response.future; }
}
void main() {
 TestWidgetsFlutterBinding.ensureInitialized();
 late DatabaseHelper db;late OfflineSyncService sync;late _Api api;late _Connectivity connectivity;
 setUp(() async {
  sqfliteFfiInit();databaseFactory=databaseFactoryFfi;
  final dir=await Directory.systemTemp.createTemp('fashionstore_sync_orchestration_');
  await databaseFactory.setDatabasesPath(dir.path);
  final owner='tenant-${DateTime.now().microsecondsSinceEpoch}:user';DatabaseHelper.activateScope(owner);
  db=DatabaseHelper.instance.forScope(owner);
  await db.insertPendingOperation({'client_operation_id':'one','operation_type':'VENTA_CONTADO_OFFLINE',
    'sucursal_id':'branch','cajero_id':'user','fecha_local':DateTime.now().toUtc().toIso8601String(),
    'monto_total':10.0,'items_json':'[]','local_status':'LOCAL_PENDIENTE','created_at':DateTime.now().toUtc().toIso8601String()});
  api=_Api();connectivity=_Connectivity();sync=OfflineSyncService(api,connectivity);
 });
 tearDown(() { sync.dispose();connectivity.dispose();DatabaseHelper.activateScope(null); });
 test('mutex is acquired before asynchronous pending read',() async {
  final first=sync.syncBatchNow();expect(await sync.syncBatchNow(),false);
  await Future<void>.delayed(const Duration(milliseconds:50));
  api.response.complete(ApiResponse(success:true,statusCode:200,data:{'results':[{'client_operation_id':'one','status':'CONFLICTO'}]}));
  expect(await first,true);expect(api.posts,1);expect(await db.getPendingCount(),0);
 });
 test('late response cannot acknowledge another account queue',() async {
  final request=sync.syncBatchNow();await Future<void>.delayed(const Duration(milliseconds:50));
  DatabaseHelper.activateScope('other:user');
  api.response.complete(ApiResponse(success:true,statusCode:200,data:{'results':[{'client_operation_id':'one','status':'CONFLICTO'}]}));
  expect(await request,false);expect(await db.getPendingCount(),1);expect(sync.lastSyncResult,isNull);
 });
 test('401 keeps pending and pauses repeated automatic attempts',() async {
  api.response.complete(ApiResponse(success:false,statusCode:401,error:'expired'));
  expect(await sync.syncBatchNow(),false);expect(await sync.syncBatchNow(),false);
  expect(api.posts,1);expect(await db.getPendingCount(),1);
 });
 test('partial response preserves pending and reports an actionable error',() async {
  api.response.complete(ApiResponse(success:true,statusCode:200,data:{'results':[]}));
  expect(await sync.syncBatchNow(),false);expect(await db.getPendingCount(),1);
  expect(sync.lastError,contains('Pendientes conservados'));
 });
}
