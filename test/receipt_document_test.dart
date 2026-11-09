import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile/config/api_config.dart';
import 'package:mobile/core/database/database_helper.dart';
import 'package:mobile/models/receipt_document.dart';
import 'package:mobile/services/api_service.dart';
import 'package:mobile/services/mobile_session_service.dart';
import 'package:mobile/services/receipt_document_service.dart';
import 'support/mobile_sessions.dart';

void main(){
 TestWidgetsFlutterBinding.ensureInitialized();
 tearDown(()=>DatabaseHelper.activateScope(null));
 Map<String,dynamic> operation()=>{'client_operation_id':'stable-local-uuid','operation_type':'VENTA_CONTADO_OFFLINE',
  'fecha_local':'2026-11-09T15:00:00Z','monto_total':24.50,'monto_recibido':30,'cambio':5.50,'sucursal_id':'branch',
  'local_status':'LOCAL_PENDIENTE','items_json':jsonEncode([{'variante_id':'v','nombre':'Camisa algodón','cantidad':2,'precio_unitario':12.25}])};
 test('durable local note retains amounts and is never central paid receipt',(){
  final note=ReceiptDocument.local(operation(),company:'Tienda');
  expect(note.data['total'],'24.50');expect(note.data['change'],'5.50');
  expect(note.data['entity_id'],'stable-local-uuid');expect(note.data['provisional'],true);
  expect(note.data['payment_status'],contains('PENDIENTE'));
  final reservation=ReceiptDocument.local({...operation(),'operation_type':'RESERVA_OFFLINE'},company:'Tienda');
  expect(reservation.data['payment_status'],'NO ACREDITA PAGO');expect(reservation.data.containsKey('received'),false);
 });
 test('offline PDF has packaged Unicode font and valid bytes without any HTTP',() async {
  var calls=0;final api=ApiService(MemorySessionStorage(),client:MockClient((_)async{calls++;return http.Response('',500);}));
  final bytes=await ReceiptDocumentService(api).provisional(ReceiptDocument.local(operation(),company:'ModaExpress'));
  expect(ascii.decode(bytes.take(5).toList()),'%PDF-');expect(bytes.length,greaterThan(5000));expect(calls,0);
  await File('${Directory.systemTemp.path}/fashionstore-receipt-mobile-f3.pdf').writeAsBytes(bytes);
  api.dispose();
 });
 test('binary canonical download renews once and never sends credentials to a foreign host',() async {
  final storage=MemorySessionStorage();var renewals=0,calls=0;
  final sessions=MobileSessionService(storage,client:MockClient((_)async{renewals++;return http.Response(jsonEncode(response(signature:'new')),200);}));
  await sessions.establish(response(signature:'old'));DatabaseHelper.activateScope(sessions.identity!.scope);
  final api=ApiService(storage,sessions:sessions,client:MockClient((r)async{
   calls++;expect(r.followRedirects,false);
   return r.headers['Authorization']!.endsWith('.old')?http.Response('',401):http.Response('%PDF-data',200,headers:{'content-type':'application/pdf'});
  }));
  expect(ascii.decode(await api.getAuthPdf('${ApiConfig.apiUrl}/receipts/sale/id/pdf')),'%PDF-data');
  expect(renewals,1);expect(calls,2);
  await expectLater(api.getAuthPdf('https://foreign.invalid/receipt.pdf'),throwsStateError);expect(calls,2);
  api.dispose();sessions.dispose();
 });
 test('late canonical PDF is discarded when identity changes',() async {
  final gate=Completer<http.Response>(),storage=MemorySessionStorage();
  final sessions=MobileSessionService(storage,client:MockClient((_)async=>http.Response('{}',200)));
  await sessions.establish(response());DatabaseHelper.activateScope(sessions.identity!.scope);
  final api=ApiService(storage,sessions:sessions,client:MockClient((_)=>gate.future));
  final pending=api.getAuthPdf('${ApiConfig.apiUrl}/receipts/sale/id/pdf');
  await Future<void>.delayed(const Duration(milliseconds:20));DatabaseHelper.activateScope('other:owner');
  gate.complete(http.Response('%PDF-private',200,headers:{'content-type':'application/pdf'}));
  await expectLater(pending,throwsStateError);api.dispose();sessions.dispose();
 });
}
