import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:mobile/core/database/database_helper.dart';
import 'package:mobile/core/services/connectivity_service.dart';
import 'package:mobile/services/api_service.dart';
import 'package:mobile/services/storage_service.dart';
import 'package:mobile/services/branch_service.dart';
import 'package:mobile/services/cart_service.dart';
import 'package:mobile/services/wallet_service.dart';
import 'package:mobile/services/reservation_service.dart';
import 'package:mobile/models/branch.dart';
import 'package:mobile/screens/shop/cart_screen.dart';

import 'channel_contracts_test.dart' show product, variant;

class _Online extends ChangeNotifier implements ConnectivityService {
  @override
  bool get isOnline => true;
  @override
  bool get wasOffline => false;
  @override
  void clearReconnectedFlag() {}
}

class _Api extends ApiService {
  _Api() : super(StorageService());
  @override
  Future<ApiResponse> postAuth(
    String url, [
    Map<String, dynamic>? body,
    Duration? timeout,
    String? expectedScope,
  ]) async => ApiResponse(
    success: true,
    statusCode: 200,
    data: {
      'valido': true,
      'codigo': 'SAVE10',
      'monto_descuento': '7.50',
      'monto_total': '67.50',
      'mensaje': 'Cupón aplicado',
    },
  );
}

class _Branches extends BranchService {
  _Branches(super.api);
  @override
  Future<List<Branch>> getBranches({bool activaOnly = true}) async => [
    Branch(id: 'branch', nombre: 'Sucursal', direccion: 'Test', activa: true),
  ];
}

class _Wallet extends WalletService {
  _Wallet(super.api, super.connectivity, super.storage);
  @override
  Future<void> fetchWallet({bool silent = false}) async {}
}

class _Reservations extends ReservationService {
  _Reservations(super.api);
  int calls = 0;
  final pending = Completer<ApiResponse>();
  @override
  Future<ApiResponse> createReservation({
    required String sucursalId,
    required List<Map<String, dynamic>> items,
    DateTime? fechaHoraEsperada,
    String? nota,
  }) {
    calls++;
    return pending.future;
  }
}

void main() {
  testWidgets(
    'two reserve taps before repaint send only once and failure retains cart',
    (tester) async {
      await tester.runAsync(() async {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
        final dir = await Directory.systemTemp.createTemp(
          'fashionstore_double_reserve_',
        );
        await databaseFactory.setDatabasesPath(dir.path);
      });
      DatabaseHelper.activateScope('double:user');
      final cart = CartService()..addItem(product(), variant());
      final api = _Api(), online = _Online();
      final wallet = _Wallet(api, online, StorageService()),
          reservations = _Reservations(api);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<CartService>.value(value: cart),
            Provider<ApiService>.value(value: api),
            Provider<BranchService>.value(value: _Branches(api)),
            Provider<ReservationService>.value(value: reservations),
            ChangeNotifierProvider<WalletService>.value(value: wallet),
            ChangeNotifierProvider<ConnectivityService>.value(value: online),
          ],
          child: const MaterialApp(home: CartScreen()),
        ),
      );
      await tester.pumpAndSettle();
      final button = find.text('Apartar con Reserva Click & Collect');
      await tester.scrollUntilVisible(
        button,
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      try {
        await tester.tap(button);
        await tester.tap(button);
        expect(reservations.calls, 1);
      } finally {
        reservations.pending.complete(
          ApiResponse(success: false, statusCode: 503, error: 'QA retry'),
        );
        await tester.pumpAndSettle();
        expect(cart.isEmpty, false);
        await tester.pumpWidget(const SizedBox.shrink());
        cart.dispose();
        wallet.dispose();
        online.dispose();
        api.dispose();
        DatabaseHelper.activateScope(null);
      }
    },
  );
  testWidgets(
    'coupon Decimal response applies and cart mutation invalidates discount',
    (tester) async {
      await tester.runAsync(() async {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
        final dir = await Directory.systemTemp.createTemp(
          'fashionstore_cart_widget_',
        );
        await databaseFactory.setDatabasesPath(dir.path);
      });
      DatabaseHelper.activateScope('widget:user');
      final cart = CartService()..addItem(product(), variant());
      final api = _Api(), online = _Online();
      final wallet = _Wallet(api, online, StorageService());
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<CartService>.value(value: cart),
            Provider<ApiService>.value(value: api),
            Provider<BranchService>.value(value: _Branches(api)),
            ChangeNotifierProvider<WalletService>.value(value: wallet),
            ChangeNotifierProvider<ConnectivityService>.value(value: online),
          ],
          child: const MaterialApp(home: CartScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(TextField).first);
      await tester.enterText(find.byType(TextField).first, 'SAVE10');
      await tester.ensureVisible(find.text('Aplicar'));
      await tester.tap(find.text('Aplicar'));
      await tester.pumpAndSettle();
      expect(find.text('SAVE10 aplicado (-Bs. 7.50)'), findsOneWidget);
      cart.updateQuantity('variant', 2);
      await tester.pumpAndSettle();
      expect(find.text('SAVE10 aplicado (-Bs. 7.50)'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      cart.dispose();
      wallet.dispose();
      online.dispose();
      api.dispose();
      DatabaseHelper.activateScope(null);
    },
  );
}
