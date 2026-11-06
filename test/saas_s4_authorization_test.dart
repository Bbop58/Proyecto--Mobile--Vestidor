import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:mobile/core/database/database_helper.dart';
import 'package:mobile/core/services/offline_authorization_service.dart';
import 'package:mobile/services/api_service.dart';
import 'package:mobile/services/storage_service.dart';

class _Api extends ApiService {
  _Api():super(StorageService());
  final reply=Completer<ApiResponse>();
  @override Future<ApiResponse> postAuth(String url,[Map<String,dynamic>? body,Duration? timeout,String? expectedScope])=>reply.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('late permit response cannot be cached after identity change',() async {
    sqfliteFfiInit();databaseFactory=databaseFactoryFfi;
    final dir=await Directory.systemTemp.createTemp('fashionstore_s4_identity_');
    await databaseFactory.setDatabasesPath(dir.path);
    final owner='s4-auth-${DateTime.now().microsecondsSinceEpoch}:user';
    DatabaseHelper.activateScope(owner);final api=_Api();
    final pending=OfflineAuthorizationService(api).prefetch('WALLET');
    DatabaseHelper.activateScope('other-$owner');
    api.reply.complete(ApiResponse(success:true,statusCode:200,data:{'grants':[{
      'client_operation_id':'late','channel':'WALLET','authorization':'proof',
      'expires_at':DateTime.now().toUtc().add(const Duration(hours:1)).toIso8601String()}]}));
    await pending;
    expect(await DatabaseHelper.instance.forScope(owner).takeAuthorization('WALLET'),isNull);
    expect(await DatabaseHelper.instance.forScope('other-$owner').takeAuthorization('WALLET'),isNull);
    DatabaseHelper.activateScope(null);api.dispose();
  });
}
