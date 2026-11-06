import 'package:flutter_test/flutter_test.dart';
import 'dart:async';
import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:mobile/models/user.dart';
import 'package:mobile/core/database/database_helper.dart';
import 'package:mobile/services/auth_service.dart';
import 'package:mobile/services/api_service.dart';
import 'package:mobile/services/storage_service.dart';

class _Storage extends StorageService {
 int tokenWrites=0;bool saved=true;
 @override Future<void> setAccessToken(String token) async {tokenWrites++;}
 @override Future<void> setRefreshToken(String token) async {}
 @override Future<void> setUserId(String id) async {}
 @override Future<bool> hasToken() async=>saved;
 @override Future<void> clearAll() async {saved=false;}
}
class _Api extends ApiService {
 _Api(super.storage);
 final operator={'id':'operator','tenant_id':'technical','access_scope':'PLATFORM','is_platform_admin':true,'email':'operator@synthetic.example.com','full_name':'Operator','is_active':true};
 @override Future<ApiResponse> post(String url,Map<String,dynamic> body) async=>ApiResponse(success:true,statusCode:200,data:{'access_token':'fake','refresh_token':'fake-refresh','user':operator});
 @override Future<ApiResponse> getAuth(String url) async=>ApiResponse(success:true,statusCode:200,data:operator);
}
class _DelayedApi extends _Api {
 _DelayedApi(super.storage);
 final response=Completer<ApiResponse>();
 @override Future<ApiResponse> post(String url,Map<String,dynamic> body)=>response.future;
 @override Future<ApiResponse> postAuth(String url,[Map<String,dynamic>? body,Duration? timeout,String? expectedScope]) async=>ApiResponse(success:true,statusCode:200,data:{});
}
void main(){TestWidgetsFlutterBinding.ensureInitialized();
 test('rejected platform login preserves the previous owners pending SQLite row',() async{
  sqfliteFfiInit();databaseFactory=databaseFactoryFfi;
  final dir=await Directory.systemTemp.createTemp('fashionstore_s5_preserve_');await databaseFactory.setDatabasesPath(dir.path);
  final owner='s5-preserve-${DateTime.now().microsecondsSinceEpoch}:old';DatabaseHelper.activateScope(owner);
  final db=await DatabaseHelper.instance.forScope(owner).database;
  await db.insert('offline_wallet_orders',{'client_operation_id':'unchanged-pending','sucursal_id':'branch','items_json':'[]','monto_total':20,'nonce_usado':4,'firma_usada':'old-proof','status':'PENDIENTE','created_at':DateTime.now().toIso8601String(),'fecha_local':DateTime.now().toIso8601String()});
  final storage=_Storage();final auth=AuthService(_Api(storage),storage);await auth.login(email:'operator@synthetic.example.com',password:'SyntheticOnly123!');
  expect((await db.query('offline_wallet_orders')).single['client_operation_id'],'unchanged-pending');
 });
 test('late login reply after logout cannot reactivate or store another session',() async{
  final storage=_Storage();final api=_DelayedApi(storage);final auth=AuthService(api,storage);
  final pending=auth.login(email:'company@synthetic.example.com',password:'SyntheticOnly123!');await auth.logout();
  api.response.complete(ApiResponse(success:true,statusCode:200,data:{'access_token':'late-token','user':{'id':'late','tenant_id':'company','access_scope':'COMPANY'}}));
  expect(await pending,false);expect(auth.isAuthenticated,false);expect(storage.tokenWrites,0);expect(DatabaseHelper.scope,isNull);
 });
 test('operator login does not activate a commercial scope or persist its token',() async{
  final storage=_Storage();final auth=AuthService(_Api(storage),storage);DatabaseHelper.activateScope('old-company:old-user');
  expect(await auth.login(email:'operator@synthetic.example.com',password:'SyntheticOnly123!'),false);
  expect(auth.isAuthenticated,false);expect(DatabaseHelper.scope,isNull);expect(storage.tokenWrites,0);expect(auth.error,contains('web'));
 });
 test('restored platform profile is not accepted as a mobile company session',() async{
  final storage=_Storage();final auth=AuthService(_Api(storage),storage);await auth.initialize();
  expect(auth.isAuthenticated,false);expect(DatabaseHelper.scope,isNull);
 });
 test('legacy profile never manufactures platform scope',(){
  final user=User.fromJson({'id':'legacy','tenant_id':'company'});
  expect(user.toJson()['access_scope'],'COMPANY');
 });
}
