import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart';
import '../config/api_config.dart';
import '../core/database/database_helper.dart';
import 'api_service.dart';

abstract class NotificationSocket {
  Stream<dynamic> get stream;
  void send(String message);
  Future<void> close();
}
class _NativeSocket implements NotificationSocket {
  final WebSocket socket;
  _NativeSocket(this.socket);
  @override Stream<dynamic> get stream=>socket;
  @override void send(String message)=>socket.add(message);
  @override Future<void> close() async {await socket.close();}
}

class NotificationRealtimeService with WidgetsBindingObserver {
  final ApiService api;
  final void Function() onChanged;
  final Future<NotificationSocket> Function(Uri) connect;
  NotificationSocket? _socket;
  StreamSubscription<dynamic>? _subscription;
  Timer? _retry;
  int _generation=0,_attempt=0;
  bool _disposed=false,_foreground=true;
  final connected=ValueNotifier<bool>(false);
  NotificationRealtimeService(this.api,{required this.onChanged,
    Future<NotificationSocket> Function(Uri)? connector})
      :connect=connector??((uri) async=>_NativeSocket(await WebSocket.connect(uri.toString()))) {
    DatabaseHelper.scopeChanges.addListener(reset);
    WidgetsBinding.instance.addObserver(this);
    reset();
  }
  @override void didChangeAppLifecycleState(AppLifecycleState state){
    _foreground=state==AppLifecycleState.resumed;reset();
  }
  void reset(){
    final generation=++_generation;
    _retry?.cancel();_retry=null;connected.value=false;
    final old=_socket;_socket=null;unawaited(old?.close());
    unawaited(_subscription?.cancel());_subscription=null;_attempt=0;
    if(!_disposed && _foreground && DatabaseHelper.scope!=null)unawaited(_open(generation));
  }
  Future<void> _open(int generation) async {
    final owner=DatabaseHelper.scope;
    bool current()=>!_disposed && generation==_generation && owner!=null && owner==DatabaseHelper.scope;
    if(!current())return;
    // Session recovery belongs to AuthService, never to a notification side effect.
    if(api.sessionCoordinator?.hasIdentity!=true)return;
    try{
      if(_attempt>0 && !await api.prepareSession(expectedScope:owner!)){
        if(current())_schedule(generation);return;
      }
      final token=await api.sessions.accessToken();
      if(!current())return;
      if(token==null){_schedule(generation);return;}
      final base=Uri.parse('${ApiConfig.apiUrl}/notifications/ws');
      final socket=await connect(base.replace(scheme:base.scheme=='https'?'wss':'ws'));
      if(!current()){await socket.close();return;}
      _socket=socket;socket.send(jsonEncode({'token':token}));
      _subscription=socket.stream.listen((raw){
        if(!current())return;
        try{final event=jsonDecode(raw as String);
          if(event is Map && event['type']=='notifications.changed' && event['revision'] is String){
            connected.value=true;_attempt=0;onChanged();
          }
        }catch(_){/* Ignore malformed or stale frames. */}
      },onError:(_){if(current())_schedule(generation);},onDone:(){
        if(current()){connected.value=false;_socket=null;_schedule(generation);}
      },cancelOnError:true);
    }catch(_){if(current())_schedule(generation);}
  }
  void _schedule(int generation){
    if(_disposed || generation!=_generation || !_foreground || DatabaseHelper.scope==null)return;
    connected.value=false;_retry?.cancel();
    final seconds=1<<(_attempt++).clamp(0,5);
    _retry=Timer(Duration(seconds:seconds),()=>unawaited(_open(generation)));
  }
  void dispose(){
    _disposed=true;DatabaseHelper.scopeChanges.removeListener(reset);
    WidgetsBinding.instance.removeObserver(this);reset();connected.dispose();
  }
}
