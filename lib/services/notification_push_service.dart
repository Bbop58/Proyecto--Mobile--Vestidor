import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/widgets.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';
import '../config/api_config.dart';
import '../core/database/database_helper.dart';
import 'api_service.dart';
import 'local_notification_service.dart';

abstract class PushStore {
  Future<Map<String,dynamic>?> read();
  Future<void> write(Map<String,dynamic> value);
}
class SecurePushStore implements PushStore {
  // flutter_secure_storage 9.2.4 retains custom Android namespace options on
  // its shared native instance. Switching those options redirects later auth
  // reads. Share the established encrypted store and use a distinct key.
  final _storage=const FlutterSecureStorage(aOptions:AndroidOptions());
  static const _key='fashionstore_push_registration_v1';
  @override Future<Map<String,dynamic>?> read() async {
    final raw=await _storage.read(key:_key);
    return raw==null?null:Map<String,dynamic>.from(jsonDecode(raw) as Map);
  }
  @override Future<void> write(Map<String,dynamic> value)=>
    _storage.write(key:_key,value:jsonEncode(value));
}
abstract class PushDriver {
  Future<void> initialize();
  Future<String?> token({required bool requestPermission});
  Stream<Map<String,dynamic>> get foreground;
  Stream<Map<String,dynamic>> get opened;
  Stream<String> get rotated;
  Future<Map<String,dynamic>?> initial();
}
class FirebasePushDriver implements PushDriver {
  String? _fid;
  bool _registering=false;
  @override Future<void> initialize() async {
    await LocalNotificationService.initialize();
    assert((){debugPrint('FCM_NATIVE_DRIVER channel_ready');return true;}());
    if(Firebase.apps.isEmpty)await Firebase.initializeApp();
    assert((){debugPrint('FCM_NATIVE_DRIVER firebase_ready');return true;}());
    await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(alert:false,badge:false,sound:false);
  }
  @override Future<String?> token({required bool requestPermission}) async {
    final settings=requestPermission?await FirebaseMessaging.instance.requestPermission():
      await FirebaseMessaging.instance.getNotificationSettings();
    if(settings.authorizationStatus!=AuthorizationStatus.authorized &&
        settings.authorizationStatus!=AuthorizationStatus.provisional){return null;}
    if(_fid!=null)return _fid;
    final completed=Completer<String>();
    _registering=true;
    final sub=FirebaseMessaging.instance.onRegistered.listen((id){if(!completed.isCompleted)completed.complete(id);});
    try{
      await FirebaseMessaging.instance.register();
      _fid=await completed.future.timeout(const Duration(seconds:60));return _fid;
    }finally{_registering=false;await sub.cancel();}
  }
  @override Stream<Map<String,dynamic>> get foreground=>FirebaseMessaging.onMessage.map((event)=>event.data);
  @override Stream<Map<String,dynamic>> get opened=>FirebaseMessaging.onMessageOpenedApp.map((event)=>event.data);
  @override Stream<String> get rotated=>FirebaseMessaging.instance.onRegistered
    .where((id)=>!_registering && id!=_fid).map((id){_fid=id;return id;});
  @override Future<Map<String,dynamic>?> initial() async =>(await FirebaseMessaging.instance.getInitialMessage())?.data;
}

class NotificationPushService extends ChangeNotifier with WidgetsBindingObserver {
  final ApiService api;final PushStore store;final PushDriver driver;
  final VoidCallback onChanged;final VoidCallback? onOpened;
  bool enabled=false,busy=false,_disposed=false,_listening=false;
  String status='Avisos del sistema desactivados';
  int _generation=0;
  Map<String,dynamic>? _document;
  Future<void> _queue=Future.value();
  final List<StreamSubscription<dynamic>> _subscriptions=[];
  String get _url=>'${ApiConfig.apiUrl}/notifications/push';
  NotificationPushService(this.api,{required this.onChanged,this.onOpened,PushStore? storage,PushDriver? messaging})
    :store=storage??SecurePushStore(),driver=messaging??FirebasePushDriver(){
    DatabaseHelper.scopeChanges.addListener(synchronize);WidgetsBinding.instance.addObserver(this);
    synchronize();
  }
  @override void didChangeAppLifecycleState(AppLifecycleState state){
    if(state==AppLifecycleState.resumed)synchronize();
  }
  void _enqueue(Future<void> Function() work){
    _queue=_queue.then((_)=>work()).catchError((Object error){
      _trace('error_${error.runtimeType}');
      if(!_disposed){status='No se pudieron activar los avisos. Reintentá con conexión.';busy=false;notifyListeners();}
    });
  }
  void _trace(String stage){assert((){debugPrint('FCM_NATIVE_STAGE $stage generation=$_generation');return true;}());}
  Future<void> get settled=>_queue;
  Future<Map<String,dynamic>> _load() async {
    if(_document!=null)return _document!;
    final saved=await store.read();
    _document=saved??{'installation_id':const Uuid().v4(),
      'installation_secret':base64UrlEncode(List.generate(32,(_)=>Random.secure().nextInt(256))),
      'opt_in':false,'pending':<dynamic>[]};
    await store.write(_document!);return _document!;
  }
  Future<void> _persist()=>store.write(_document!);
  Future<void> _flush(Map<String,dynamic> doc) async {
    final pending=List<dynamic>.from(doc['pending'] as List? ?? []);
    for(final raw in pending){
      final binding=Map<String,dynamic>.from(raw as Map);
      final result=await api.post('$_url/unregister',{
        'installation_id':doc['installation_id'],'installation_secret':doc['installation_secret'],
        'binding_id':binding['binding_id']});
      if(!result.success)return;
      (doc['pending'] as List).removeWhere((item)=>item['binding_id']==binding['binding_id']);await _persist();
    }
  }
  void synchronize(){
    final generation=++_generation,owner=DatabaseHelper.scope;
    _enqueue(()=>_synchronize(owner,generation));
  }
  Future<void> _synchronize(String? owner,int generation,{bool request=false}) async {
    _trace('storage');
    final doc=await _load();if(_disposed || generation!=_generation)return;
    var binding=doc['binding'] as Map?;
    if(binding!=null && binding['owner']!=owner){
      (doc['pending'] as List).add(Map<String,dynamic>.from(binding));doc.remove('binding');await _persist();
    }
    await _flush(doc);
    if(_disposed || generation!=_generation)return;
    enabled=false;
    if(owner==null || doc['opt_in']!=true){status='Avisos del sistema desactivados';notifyListeners();return;}
    busy=true;notifyListeners();
    try{
      _trace('initialize');
      await driver.initialize().timeout(const Duration(seconds:15));
      _trace('registration');
      final token=await driver.token(requestPermission:request).timeout(const Duration(seconds:65));
      _trace('registration_returned_current_${generation==_generation}');
      if(_disposed || generation!=_generation || owner!=DatabaseHelper.scope)return;
      if(token==null){
        final old=doc.remove('binding');if(old!=null)(doc['pending'] as List).add(old);
        await _persist();await _flush(doc);status='Activá el permiso de notificaciones en Android.';return;
      }
      final result=await api.putAuth('$_url/devices',{
        'installation_id':doc['installation_id'],'installation_secret':doc['installation_secret'],
        'token':token,'platform':'android'});
      _trace('server_${result.statusCode}');
      if(!result.success)throw StateError('Push registration failed');
      binding={'owner':owner,'binding_id':result.data['binding_id']};
      if(_disposed || generation!=_generation || owner!=DatabaseHelper.scope){
        (doc['pending'] as List).add(binding);await _persist();return;
      }
      doc['binding']=binding;await _persist();enabled=true;status='Avisos del sistema activados';
      if(!_listening){
        _listening=true;
        _subscriptions.add(driver.foreground.listen((data){if(_matches(data))onChanged();}));
        _subscriptions.add(driver.opened.listen((data){if(_matches(data))onOpened?.call();}));
        _subscriptions.add(driver.rotated.listen((_){synchronize();}));
        final initial=await driver.initial();if(initial!=null && _matches(initial))onOpened?.call();
      }
    }finally{if(!_disposed && generation==_generation){busy=false;notifyListeners();}}
  }
  bool _matches(Map<String,dynamic> event){
    final binding=_document?['binding'] as Map?;
    return !_disposed && binding!=null && binding['owner']==DatabaseHelper.scope &&
      binding['binding_id']==event['binding_id'];
  }
  Future<void> enable() async {
    if(busy || DatabaseHelper.scope==null)return;
    final generation=++_generation,owner=DatabaseHelper.scope;
    _enqueue(() async {final doc=await _load();doc['opt_in']=true;await _persist();
      await _synchronize(owner,generation,request:true);});
    await _queue;
  }
  Future<void> disable() async {
    ++_generation;
    _enqueue(() async {final doc=await _load();doc['opt_in']=false;
      final binding=doc.remove('binding');if(binding!=null)(doc['pending'] as List).add(binding);
      await _persist();await _flush(doc);
      if(!_disposed){enabled=false;status='Avisos del sistema desactivados';notifyListeners();}
    });await _queue;
  }
  @override void dispose(){
    _disposed=true;++_generation;DatabaseHelper.scopeChanges.removeListener(synchronize);
    WidgetsBinding.instance.removeObserver(this);for(final sub in _subscriptions){unawaited(sub.cancel());}
    super.dispose();
  }
}
