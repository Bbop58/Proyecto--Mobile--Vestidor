import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/services/wallet_service.dart';
import 'package:mobile/services/api_service.dart';
import 'package:mobile/services/storage_service.dart';
import 'package:mobile/core/services/connectivity_service.dart';
import 'package:mobile/core/database/database_helper.dart';
class _Network extends ChangeNotifier implements ConnectivityService {
 @override bool get isOnline=>true;
 @override bool get wasOffline=>false;
 @override void clearReconnectedFlag(){}
}
class _Api extends ApiService {
 _Api():super(StorageService());
 final pending=Completer<ApiResponse>();
 @override Future<ApiResponse> getAuth(String url)=>pending.future;
}
void main(){
 TestWidgetsFlutterBinding.ensureInitialized();
 test('availability follows the company response without changing wallet state',() async {
  DatabaseHelper.activateScope('company-a:user');final api=_Api();final net=_Network();final wallet=WalletService(api,net,StorageService());
  final work=wallet.fetchPayPalAvailability();api.pending.complete(ApiResponse(success:true,statusCode:200,data:{'enabled':true,'mode':'sandbox'}));await work;
  expect(wallet.paypalAvailable,true);expect(wallet.paypalMode,'sandbox');expect(wallet.saldo,0);
  DatabaseHelper.activateScope('company-b:other');expect(wallet.paypalAvailable,isNull);wallet.dispose();net.dispose();api.dispose();DatabaseHelper.activateScope(null);
 });
 test('late availability from a previous owner is discarded',() async {
  DatabaseHelper.activateScope('company-a:user');final api=_Api();final net=_Network();final wallet=WalletService(api,net,StorageService());
  final work=wallet.fetchPayPalAvailability();DatabaseHelper.activateScope('company-b:other');api.pending.complete(ApiResponse(success:true,statusCode:200,data:{'enabled':true,'mode':'sandbox'}));await work;
  expect(wallet.paypalAvailable,isNull);wallet.dispose();net.dispose();api.dispose();DatabaseHelper.activateScope(null);
 });
}
