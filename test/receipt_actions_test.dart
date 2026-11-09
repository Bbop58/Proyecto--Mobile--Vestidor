import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mobile/core/database/database_helper.dart';
import 'package:mobile/core/services/connectivity_service.dart';
import 'package:mobile/models/receipt_document.dart';
import 'package:mobile/services/api_service.dart';
import 'package:mobile/services/receipt_document_service.dart';
import 'package:mobile/widgets/receipt_actions.dart';
import 'support/mobile_sessions.dart';

class Conn extends ConnectivityService { bool online=true;@override bool get isOnline=>online; }
class Documents extends ReceiptDocumentService {
 Documents():super(ApiService(MemorySessionStorage()));
 int exports=0;final ids=<String>[];bool fail=true;Completer<Uint8List>? gate;
 @override Future<Uint8List> pdf(ReceiptRef ref)=>gate?.future??Future.value(Uint8List.fromList([1,2,3]));
 @override Future<void> export(Uint8List bytes,String id)async{exports++;}
 @override Future<bool> emailEnabled()async=>true;
 @override Future<String?> emailAddress(ReceiptRef ref)async=>'customer@example.com';
 @override Future<Map<String,dynamic>> email(ReceiptRef ref,String recipient,String operationId)async{
  ids.add(operationId);if(fail)throw StateError('No se pudo confirmar');
  return {'status':'ACCEPTED','message':'Correo aceptado para envío'};
 }
}
void main(){
 setUp(()=>DatabaseHelper.activateScope('tenant:person'));
 tearDown(()=>DatabaseHelper.activateScope(null));
 Widget app(Documents service,Conn conn)=>ChangeNotifierProvider<ConnectivityService>.value(value:conn,
  child:MaterialApp(home:Scaffold(body:SingleChildScrollView(child:ReceiptActions(reference:const ReceiptRef('sale','id'),service:service)))));
 testWidgets('PDF callback is discarded after account switch',(tester) async {
  final service=Documents()..gate=Completer<Uint8List>(),conn=Conn();
  await tester.pumpWidget(app(service,conn));await tester.tap(find.text('Descargar PDF'));await tester.pump();
  DatabaseHelper.activateScope('another:person');service.gate!.complete(Uint8List.fromList([1]));await tester.pumpAndSettle();
  expect(service.exports,0);await tester.pumpWidget(const SizedBox());conn.dispose();service.api.dispose();
 });
 testWidgets('email is explicit and network retry reuses operation UUID',(tester)async{
  final service=Documents(),conn=Conn();await tester.pumpWidget(app(service,conn));
  await tester.tap(find.text('Enviar al correo'));await tester.pumpAndSettle();
  expect(find.text('customer@example.com'),findsOneWidget);expect(service.ids,isEmpty);
  await tester.tap(find.text('Confirmar envío'));await tester.pumpAndSettle();expect(service.ids.length,1);
  service.fail=false;await tester.tap(find.text('Enviar al correo'));await tester.pumpAndSettle();
  await tester.tap(find.text('Confirmar envío'));await tester.pumpAndSettle();
  expect(service.ids.length,2);expect(service.ids[0],service.ids[1]);expect(find.text('Correo aceptado para envío'),findsOneWidget);
  await tester.pump(const Duration(seconds:2));await tester.pumpWidget(const SizedBox());conn.dispose();service.api.dispose();
 });
 testWidgets('offline disables confirmed receipt transport and fits narrow text-scaled screen',(tester)async{
  final service=Documents(),conn=Conn()..online=false;
  tester.view.physicalSize=const Size(320,900);tester.view.devicePixelRatio=1;
  addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MediaQuery(data:const MediaQueryData(textScaler:TextScaler.linear(2)),child:app(service,conn)));
  final buttons=tester.widgetList<OutlinedButton>(find.byType(OutlinedButton)).toList();
  expect(buttons.every((b)=>b.onPressed==null),true);expect(tester.takeException(),null);
  await tester.pumpWidget(const SizedBox());conn.dispose();service.api.dispose();
 });
}
