import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:mobile/core/database/database_helper.dart';
import 'package:mobile/core/services/connectivity_service.dart';
import 'package:mobile/models/product.dart';
import 'package:mobile/models/category.dart';
import 'package:mobile/services/api_service.dart';
import 'package:mobile/services/storage_service.dart';
import 'package:mobile/services/cart_service.dart';
import 'package:mobile/services/product_service.dart';
import 'package:mobile/services/category_service.dart';
import 'package:mobile/services/season_service.dart';
import 'package:mobile/services/notification_service.dart';
import 'package:mobile/services/favorite_service.dart';
import 'package:mobile/screens/shop/catalog_screen.dart';

class _Network extends ChangeNotifier implements ConnectivityService {
  @override
  bool get isOnline => true;
  @override
  bool get wasOffline => false;
  @override
  void clearReconnectedFlag() {}
}

class _Categories extends CategoryService {
  _Categories(super.api);
  @override
  Future<List<Category>> getCategories() async => [];
}

class _Seasons extends SeasonService {
  _Seasons(super.api);
  @override
  Future<List<Season>> getSeasons() async => [];
}

class _Products extends ProductService {
  _Products(super.api);
  @override
  Future<List<Product>> getProducts({
    String? categoriaId,
    String? temporada,
    String? search,
    bool? activo = true,
  }) async => [];
}

class _Notifications extends NotificationService {
  _Notifications(super.api);
  @override
  Future<void> fetchUnreadCount() async {}
}

void main() {
  testWidgets(
    'an authoritative empty online catalog does not resurrect stale cached products',
    (tester) async {
      final network = _Network(),
          api = ApiService(StorageService()),
          cart = CartService();
      late FavoriteService favorites;
      await tester.runAsync(() async {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
        final dir = await Directory.systemTemp.createTemp(
          'fashionstore_catalog_widget_',
        );
        await databaseFactory.setDatabasesPath(dir.path);
        DatabaseHelper.activateScope('catalog-widget:user');
        await DatabaseHelper.instance.cacheProducts([
          {
            'id': 'stale',
            'nombre': 'Producto retirado QA',
            'precio_base': 10,
            'variantes_json': '[]',
          },
        ]);
        favorites = FavoriteService(api, network, StorageService());
        await favorites.loadLocalFavorites();
      });
      final notifications = _Notifications(api);
      await tester.runAsync(() async {
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<CartService>.value(value: cart),
              ChangeNotifierProvider<ConnectivityService>.value(value: network),
              ChangeNotifierProvider<FavoriteService>.value(value: favorites),
              ChangeNotifierProvider<NotificationService>.value(
                value: notifications,
              ),
              Provider<CategoryService>.value(value: _Categories(api)),
              Provider<SeasonService>.value(value: _Seasons(api)),
              Provider<ProductService>.value(value: _Products(api)),
            ],
            child: const MaterialApp(home: CatalogScreen()),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.text('Producto retirado QA'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      favorites.dispose();
      notifications.dispose();
      cart.dispose();
      network.dispose();
      api.dispose();
      DatabaseHelper.activateScope(null);
    },
  );
}
