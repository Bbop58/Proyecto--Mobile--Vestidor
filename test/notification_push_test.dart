import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/database/database_helper.dart';
import 'package:mobile/services/notification_push_service.dart';
import 'package:mobile/services/api_service.dart';
import 'package:mobile/services/storage_service.dart';

class MemoryPushStore implements PushStore {
  Map<String,dynamic>? value;
  @override Future<Map<String,dynamic>?> read()async=>value;
  @override Future<void> write(Map<String,dynamic> v)async{value=jsonDecode(jsonEncode(v));}
}
class Driver implements PushDriver {
  final messages=StreamController<Map<String,dynamic>>.broadcast();
  final taps=StreamController<Map<String,dynamic>>.broadcast();
  final rotations=StreamController<String>.broadcast();
  bool allowed=true;
  @override Future<void> initialize()async{}
  @override Future<String?> token({required bool requestPermission})async=>allowed?'qa-provider-token':null;
  @override Stream<Map<String,dynamic>> get foreground=>messages.stream;
  @override Stream<Map<String,dynamic>> get opened=>taps.stream;
  @override Stream<String> get rotated=>rotations.stream;
  @override Future<Map<String,dynamic>?> initial()async=>null;
}
class PushApi extends ApiService {
  PushApi():super(StorageService());
  int registrations=0,revocations=0;bool offline=false;
  @override Future<ApiResponse> putAuth(String url,Map<String,dynamic> body)async{
    registrations++;return ApiResponse(success:true,statusCode:200,data:{'binding_id':'binding-$registrations'});
  }
  @override Future<ApiResponse> post(String url,Map<String,dynamic> body)async{
    revocations++;return ApiResponse(success:!offline,statusCode:offline?0:200);
  }
}
void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(()=>DatabaseHelper.activateScope(null));
  test('switch account invalidates foreground/tap callbacks and rebinds installation',()async{
    DatabaseHelper.activateScope('a:user');final api=PushApi(),store=MemoryPushStore(),driver=Driver();
    var refreshes=0,taps=0;
    final service=NotificationPushService(api,onChanged:()=>refreshes++,onOpened:()=>taps++,storage:store,messaging:driver);
    await service.settled;expect(api.registrations,0);await service.enable();
    driver.messages.add({'binding_id':'binding-1'});await Future<void>.delayed(Duration.zero);expect(refreshes,1);
    DatabaseHelper.activateScope('b:user');await service.settled;expect(api.registrations,2);expect(api.revocations,1);
    driver.messages.add({'binding_id':'binding-1'});driver.taps.add({'binding_id':'binding-1'});
    await Future<void>.delayed(Duration.zero);expect(refreshes,1);expect(taps,0);
    driver.messages.add({'binding_id':'binding-2'});await Future<void>.delayed(Duration.zero);expect(refreshes,2);
    service.dispose();
  });
  test('offline logout persists revocation, next connection clears it without enabling anonymous push',()async{
    DatabaseHelper.activateScope('a:user');final api=PushApi(),store=MemoryPushStore(),driver=Driver();
    final service=NotificationPushService(api,onChanged:(){},storage:store,messaging:driver);
    await service.settled;await service.enable();api.offline=true;DatabaseHelper.activateScope(null);await service.settled;
    expect((store.value!['pending'] as List).length,1);expect(store.value!['binding'],null);
    api.offline=false;service.synchronize();await service.settled;
    expect(store.value!['pending'],isEmpty);expect(service.enabled,false);service.dispose();
  });
  test('denied permission does not register or claim activation',()async{
    DatabaseHelper.activateScope('a:user');final api=PushApi(),driver=Driver()..allowed=false;
    final service=NotificationPushService(api,onChanged:(){},storage:MemoryPushStore(),messaging:driver);
    await service.settled;await service.enable();expect(api.registrations,0);expect(service.enabled,false);service.dispose();
  });
}
