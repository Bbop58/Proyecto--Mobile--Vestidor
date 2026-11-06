import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:mobile/core/database/database_helper.dart';
import 'package:mobile/core/services/connectivity_service.dart';
import 'package:mobile/services/api_service.dart';
import 'package:mobile/services/storage_service.dart';
import 'package:mobile/services/wallet_service.dart';

class _Online extends ChangeNotifier implements ConnectivityService {
  @override bool get isOnline => true;
  @override bool get wasOffline => false;
  @override void clearReconnectedFlag() {}
}

class _Storage extends StorageService {
  @override Future<String?> getUserId() async => 'user';
}

class _Api extends ApiService {
  _Api(this.outcome, {this.held = 0}) : super(_Storage());
  final String outcome;
  final double held;
  double balance = 20;
  int posts = 0;
  @override Future<ApiResponse> getAuth(String url) async => ApiResponse(success: true, statusCode: 200,
    data: url.endsWith('/history') ? [] : {'id': 'wallet', 'user_id': 'user', 'saldo_actual': balance,
      'saldo_retenido': held, 'nonce_secuencia': 1, 'firma_balance': 'server-proof', 'moneda': 'BOB'});
  @override Future<ApiResponse> postAuth(String url, [Map<String, dynamic>? body, Duration? timeout, String? expectedScope]) async {
    if(url.endsWith('/authorizations')) return ApiResponse(success:true,statusCode:200,data:{'grants':[]});
    posts++;
    if (outcome == 'TIMEOUT') return ApiResponse(success: false, statusCode: 504, error: 'unknown result');
    final id = url.endsWith('/wallet/pay') ? body!['client_operation_id'] : (body!['orders'] as List).first['client_operation_id'];
    if (outcome == 'CONFIRMADA') balance = 10;
    return ApiResponse(success: true, statusCode: 200, data: {'nuevo_saldo':balance,'saldo_retenido':held,'nuevo_nonce':2,'nueva_firma':'verified-after-sync','results': [
      {'client_operation_id': id, 'status': outcome,
        if (outcome == 'CONFIRMADA') 'receipt_number': 'SERVER-RECEIPT',
        if (outcome == 'CONFIRMADA') 'server_entity_id': 'server-sale',
        if (outcome != 'CONFIRMADA') 'error_detail': 'Rejected by server'}]});
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final outcome in ['CONFIRMADA', 'CONFLICTO', 'TIMEOUT', 'HELD']) {
    test('wallet checkout reports $outcome according to central confirmation', () async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final directory = await Directory.systemTemp.createTemp('fashionstore_phase3_wallet_');
      await databaseFactory.setDatabasesPath(directory.path);
      DatabaseHelper.activateScope('company-$outcome:user');
      final api = _Api(outcome, held: outcome == 'HELD' ? 15 : 0);
      final connectivity = _Online();
      final wallet = WalletService(api, connectivity, _Storage());
      await wallet.fetchWallet();
      final payment = wallet.payWithWallet(sucursalId: 'branch', totalAmount: 10,
        items: [{'variante_id': 'variant', 'cantidad': 1, 'precio_unitario': 10}]);
      if (outcome == 'HELD') {
        await expectLater(payment, throwsException);
        expect(api.posts, 0);
      } else {
        final result = await payment;
        if (outcome == 'CONFIRMADA') {
          expect(result['success'], true);
          expect(result['offline_queued'], false);
          expect(result['server_receipt'], 'SERVER-RECEIPT');
        } else if (outcome == 'CONFLICTO') {
          expect(result['success'], false);
          expect(result['error'], 'Rejected by server');
        } else {
          expect(result['success'], true);
          expect(result['offline_queued'], true);
          expect(result['server_receipt'], isNull);
        }
      }
      wallet.dispose();
      connectivity.dispose();
      DatabaseHelper.activateScope(null);
    });
  }
}
