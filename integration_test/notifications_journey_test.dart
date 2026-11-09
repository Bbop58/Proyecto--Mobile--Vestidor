import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:mobile/main.dart' as app;
import 'package:mobile/config/api_config.dart';
import 'package:mobile/services/auth_service.dart';
import 'package:mobile/services/api_service.dart';
import 'package:mobile/services/notification_service.dart';
import 'package:mobile/screens/notifications/notifications_screen.dart';

void main(){
 IntegrationTestWidgetsFlutterBinding.ensureInitialized();
 testWidgets('C2 native WebSocket and Firebase registration without transport doubles',(tester)async{
  const email=String.fromEnvironment('QA_EMAIL');
  const password=String.fromEnvironment('QA_PASSWORD');
  const branch=String.fromEnvironment('QA_BRANCH');
  const variant=String.fromEnvironment('QA_VARIANT');
  const tenant=String.fromEnvironment('QA_TENANT');
  const slug=String.fromEnvironment('QA_SLUG');
  expect(['http://10.0.2.2:58013','https://proyecto-backend-vestidor-production.up.railway.app'].contains(ApiConfig.baseUrl),true);
  expect(email.startsWith('pushqa-') && email.endsWith('@example.com') && password.isNotEmpty,true);
  Future<void> until(bool Function() ready,String description,{int seconds=90})async{
   final end=DateTime.now().add(Duration(seconds:seconds));
   while(!ready() && DateTime.now().isBefore(end)){
    await tester.pump(const Duration(milliseconds:100));
    await Future<void>.delayed(const Duration(milliseconds:100));
   }
   expect(ready(),true,reason:description);
  }
  await tester.pumpWidget(const app.MyApp());await tester.pump();
  final context=tester.element(find.byType(app.AuthWrapper).first);
  final auth=context.read<AuthService>();
  await until(()=>!auth.isLoading,'Session initialization');
  if(auth.sessionRecoveryNeeded){await auth.retrySession();await tester.pump();}
  if(auth.isAuthenticated)expect(await auth.logout(),true);
  expect(await auth.login(email:email,password:password),true,reason:auth.error);
  await tester.pump();
  final api=context.read<ApiService>();
  final notices=context.read<NotificationService>();
  app.appNavigationKey.currentState!.push(MaterialPageRoute<void>(builder:(_)=>const NotificationsScreen()));
  await tester.pump();
  await until(()=>notices.realtime.connected.value,'Authenticated native socket');
  // Start with FCM disabled so it cannot disguise a missing WebSocket update.
  await notices.push.disable();
  final created=await api.postAuth('${ApiConfig.apiUrl}/reservas',{
   'sucursal_id':branch,'fecha_hora_esperada':DateTime.now().toUtc().add(const Duration(hours:3)).toIso8601String(),
   'items':[{'variante_id':variant,'cantidad':1}]
  });
  expect(created.success,true,reason:created.error);
  final id=created.data['id'].toString(),code=created.data['codigo'].toString();
  final client=http.Client();Map<String,dynamic>? admin;
  try{
   final login=await client.post(Uri.parse('${ApiConfig.apiUrl}/auth/login'),
    headers:{'Content-Type':'application/json'},body:jsonEncode({
     'tenant_id':tenant,'email':'admin@$slug.com','password':'Password123!'}));
   expect(login.statusCode,200);admin=jsonDecode(login.body) as Map<String,dynamic>;
   final prepared=await client.patch(Uri.parse('${ApiConfig.apiUrl}/reservas/$id/preparar'),
    headers:{'Authorization':'Bearer ${admin['access_token']}','Content-Type':'application/json'},body:'{}');
   expect(prepared.statusCode,200);
   await until(()=>notices.notifications.any((n)=>n.type=='RESERVATION_READY' && n.message.contains(code)),
     'Ready notification from real WebSocket');
   expect(notices.realtime.connected.value,true);
   expect(find.textContaining(code),findsWidgets);
   // The host grants Android permission on this QA emulator only; exercise
   // the real opt-in button and Firebase SDK after the WS-only assertion.
   await tester.tap(find.text('Activar avisos del sistema'));await tester.pump();
   await until(()=>notices.push.enabled || (!notices.push.busy && notices.push.status.startsWith('No se')),
     'Firebase registration',seconds:100);
   expect(notices.push.enabled,true,reason:notices.push.status);
   debugPrint('NOTIFICATIONS_NATIVE_QA_PASS company=$slug websocket=true push_registration=true');
  }finally{
   if(admin!=null){await client.post(Uri.parse('${ApiConfig.apiUrl}/auth/logout'),
    headers:{'Authorization':'Bearer ${admin['access_token']}','Content-Type':'application/json'},
    body:jsonEncode({'refresh_token':admin['refresh_token']}));}
   client.close();
  }
  // Intentionally retain this synthetic customer's durable session and push
  // opt-in for the separate normal-APK background/tap/reboot acceptance.
  // Invoke flutter test with --no-uninstall or the CLI removes this app/data.
 },timeout:const Timeout(Duration(minutes:5)));
}
