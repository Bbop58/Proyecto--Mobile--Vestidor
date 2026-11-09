import 'dart:async';
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main(){
 IntegrationTestWidgetsFlutterBinding.ensureInitialized();
 testWidgets('C2 isolate real Firebase registration stages',(tester)async{
  final result=<String,Object?>{};
  await tester.pumpWidget(const MaterialApp(home:Scaffold(body:Text('Firebase QA'))));
  String stage='initialize';StreamSubscription<String>? subscription;
  try{
   await Firebase.initializeApp().timeout(const Duration(seconds:60));
   result['initialized']=true;stage='permission';
   final messaging=FirebaseMessaging.instance;
   final settings=await messaging.getNotificationSettings().timeout(const Duration(seconds:15));
   result['permission']=settings.authorizationStatus.name;
   final registered=Completer<void>();
   subscription=messaging.onRegistered.listen((id){
    result['identifier_received']=id.isNotEmpty;
    if(!registered.isCompleted)registered.complete();
   },onError:(Object error,StackTrace stack){if(!registered.isCompleted)registered.completeError(error,stack);});
   stage='register_future';
   await messaging.register().timeout(const Duration(seconds:45));result['register_completed']=true;
   stage='registration_callback';
   await registered.future.timeout(const Duration(seconds:20));
   result['success']=true;
  }catch(error){
   result['failed_stage']=stage;
   result['error_type']=error.runtimeType.toString();
   if(error is FirebaseException)result['firebase_code']=error.code;
   rethrow;
  }finally{
   await subscription?.cancel();debugPrint('FIREBASE_NATIVE_DIAGNOSTIC ${jsonEncode(result)}');
  }
 },timeout:const Timeout(Duration(minutes:3)));
}
