import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/database/database_helper.dart';
import 'package:mobile/services/api_service.dart';
import 'package:mobile/services/mobile_session_service.dart';
import 'package:mobile/services/storage_service.dart';
import 'package:mobile/services/notification_realtime_service.dart';

class RealtimeSessions extends MobileSessionService {
  RealtimeSessions():super(StorageService());
  @override bool get hasIdentity=>true;
  @override Future<String?> accessToken({bool forceRefresh=false,String? rejectedAccessToken})async=>'only-test-access';
}
class RealtimeApi extends ApiService {
  final coordinator=RealtimeSessions();
  RealtimeApi():super(StorageService());
  @override MobileSessionService get sessions=>coordinator;
  @override MobileSessionService? get sessionCoordinator=>coordinator;
  @override Future<bool> prepareSession({required String expectedScope,bool revalidate=true})async=>true;
}
class Socket implements NotificationSocket {
  final events=StreamController<dynamic>.broadcast();
  final sent=<String>[];bool closed=false;
  @override Stream<dynamic> get stream=>events.stream;
  @override void send(String value)=>sent.add(value);
  @override Future<void> close()async{closed=true;}
}
Future<void> microtasks()async{for(var i=0;i<8;i++){await Future<void>.delayed(Duration.zero);}}
void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(()=>DatabaseHelper.activateScope(null));
  test('auth is in frame, account switch discards old event and closes socket',()async{
    DatabaseHelper.activateScope('a:user');final sockets=<Socket>[],urls=<Uri>[];var refreshed=0;
    final service=NotificationRealtimeService(RealtimeApi(),onChanged:()=>refreshed++,connector:(uri)async{
      urls.add(uri);final socket=Socket();sockets.add(socket);return socket;
    });
    await microtasks();expect(urls.single.query,isEmpty);expect(jsonDecode(sockets[0].sent.single)['token'],'only-test-access');
    sockets[0].events.add(jsonEncode({'type':'notifications.changed','revision':'one'}));await microtasks();
    expect(refreshed,1);expect(service.connected.value,true);
    DatabaseHelper.activateScope('b:user');await microtasks();expect(sockets[0].closed,true);
    sockets[0].events.add(jsonEncode({'type':'notifications.changed','revision':'two'}));await microtasks();expect(refreshed,1);
    service.dispose();
  });
  test('connection finishing after logout is closed before sending credentials',()async{
    DatabaseHelper.activateScope('a:user');final pending=Completer<NotificationSocket>();
    final service=NotificationRealtimeService(RealtimeApi(),onChanged:(){},connector:(_)=>pending.future);
    await microtasks();DatabaseHelper.activateScope(null);final socket=Socket();pending.complete(socket);await microtasks();
    expect(socket.closed,true);expect(socket.sent,isEmpty);service.dispose();
  });
}
