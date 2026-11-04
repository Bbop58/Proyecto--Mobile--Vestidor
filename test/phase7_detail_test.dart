import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mobile/config/theme.dart';
import 'package:mobile/core/database/database_helper.dart';
import 'package:mobile/core/services/connectivity_service.dart';
import 'package:mobile/models/product.dart';
import 'package:mobile/services/api_service.dart';
import 'package:mobile/services/storage_service.dart';
import 'package:mobile/services/product_service.dart';
import 'package:mobile/services/inventory_service.dart';
import 'package:mobile/services/cart_service.dart';
import 'package:mobile/services/favorite_service.dart';
import 'package:mobile/screens/shop/product_detail_screen.dart';

import 'channel_contracts_test.dart' show variant;

class _Online extends ChangeNotifier implements ConnectivityService {
  @override
  bool get isOnline => true;
  @override
  bool get wasOffline => false;
  @override
  void clearReconnectedFlag() {}
}

class _Products extends ProductService {
  _Products(super.api);
  @override
  Future<Product?> getProductById(String id) async => Product(
    id: 'product',
    codigo: 'QA',
    nombre: 'Camisa ejecutiva de corte italiano',
    descripcion: 'Algodón para uso diario.',
    precioBase: 100,
    precioOferta: 70,
    enOferta: true,
    activo: true,
    variantes: [variant()],
  );
}

class _Inventory extends InventoryService {
  _Inventory(super.api);
  @override
  Future<List<InventoryAvailability>> getProductAvailability({
    required String productoId,
    String? talla,
    String? color,
  }) async => [];
}

void main() {
  for (final dark in [false, true]) {
    testWidgets(
      'detail at 320px, 200% text, dark=$dark keeps price and actions visible',
      (tester) async {
        tester.view.physicalSize = const Size(320, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        DatabaseHelper.activateScope('phase7:detail');
        final api = ApiService(StorageService()),
            online = _Online(),
            cart = CartService();
        final favorites = FavoriteService(api, online, StorageService());
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              Provider<ProductService>.value(value: _Products(api)),
              Provider<InventoryService>.value(value: _Inventory(api)),
              ChangeNotifierProvider<CartService>.value(value: cart),
              ChangeNotifierProvider<FavoriteService>.value(value: favorites),
            ],
            child: MaterialApp(
              theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(2)),
                child: child!,
              ),
              home: const ProductDetailScreen(productId: 'product'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Añadir al Carrito'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('Descripción'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        favorites.dispose();
        cart.dispose();
        online.dispose();
        api.dispose();
        DatabaseHelper.activateScope(null);
      },
    );
  }
}
