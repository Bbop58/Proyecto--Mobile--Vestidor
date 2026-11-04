// Explicit local-only live contract test; not part of the default unit suite.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/config/api_config.dart';
import 'package:mobile/core/database/database_helper.dart';
import 'package:mobile/services/api_service.dart';
import 'package:mobile/services/storage_service.dart';
import 'package:mobile/services/product_service.dart';
import 'package:mobile/services/branch_service.dart';
import 'package:mobile/services/inventory_service.dart';
import 'package:mobile/services/reservation_service.dart';
import 'package:mobile/services/sale_service.dart';
import 'package:mobile/services/category_service.dart';
import 'package:mobile/services/season_service.dart';

class _Session extends StorageService {
  String? token;
  @override
  Future<String?> getAccessToken() async => token;
}

void main() {
  test('live Dart consumers login catalog availability reservation cancel wallet sale history profile notifications logout', () async {
    if (ApiConfig.baseUrl != 'http://127.0.0.1:58001') {
      throw StateError('Dedicated local phase5 API required');
    }
    HttpOverrides.global = null;
    final storage = _Session(), api = ApiService(_Session());
    final login = await api.post(ApiConfig.loginUrl, {
      'email': 'phase5-cliente@example.com',
      'password': 'Phase5-Local-Only!',
    });
    expect(login.success, true, reason: login.error);
    storage.token = login.data['access_token'];
    DatabaseHelper.activateScope(
      '${login.data['user']['tenant_id']}:${login.data['user']['id']}',
    );
    final client = ApiService(storage);
    final products = await ProductService(client)
        .getProducts(search: 'Camisa QA');
    expect(products, isNotEmpty);
    final product = await ProductService(client)
        .getProductById(products.first.id);
    expect(product!.precioEfectivo, 70);
    expect(await CategoryService(client).getCategories(), isNotEmpty);
    await SeasonService(client).getSeasons();
    final branches = await BranchService(client).getBranches();
    expect(branches, isNotEmpty);
    final variant = product.variantes.first;
    final available = await InventoryService(client).getProductAvailability(
      productoId: product.id,
      talla: variant.talla,
      color: variant.color,
    );
    expect(available, isNotEmpty);
    final reservations = ReservationService(client);
    final created = await reservations.createReservation(
      sucursalId: branches.first.id,
      items: [
        {'variante_id': variant.id, 'cantidad': 1},
      ],
    );
    expect(created.success, true, reason: created.error);
    final own = await reservations.getMyReservations();
    expect(own.any((r) => r.id == created.data['id'] && r.total == 75), true);
    expect(
      (await reservations.cancelReservation(created.data['id'])).success,
      true,
    );
    final wallet = await client.getAuth(ApiConfig.walletMeUrl);
    expect(wallet.success, true, reason: wallet.error);
    final id =
        '${DateTime.now().microsecondsSinceEpoch.toRadixString(16).padLeft(8, '0').substring(0, 8)}-1234-4234-8234-123456789abc';
    final payment = await client.postAuth(ApiConfig.walletSyncOfflineUrl, {
      'orders': [
        {
          'client_operation_id': id,
          'sucursal_id': branches.first.id,
          'monto_total': 75,
          'items': [
            {'variante_id': variant.id, 'cantidad': 1, 'precio_unitario': 75},
          ],
        },
      ],
    });
    expect(payment.success, true, reason: payment.error);
    expect(payment.data['results'].first['status'], 'CONFIRMADA');
    final sales = await SaleService(client).getMySales();
    expect(
      sales.any((s) => s.metodoPago == 'BILLETERA' && s.total == 75),
      true,
    );
    final favorite = await client.postAuth('${ApiConfig.apiUrl}/favorites', {
      'product_id': product.id,
    });
    expect(favorite.success, true);
    final favorites = await client.getAuth('${ApiConfig.apiUrl}/favorites');
    expect(
      (favorites.data as List).any((f) => f['producto']['id'] == product.id),
      true,
    );
    expect(
      (await client.deleteAuth('${ApiConfig.apiUrl}/favorites/${product.id}'))
          .success,
      true,
    );
    expect(
      (await client.putAuth(ApiConfig.profileUrl, {
        'full_name': 'Cliente QA Live',
      })).success,
      true,
    );
    expect(
      (await client.postAuth(ApiConfig.markAllNotificationsReadUrl)).success,
      true,
    );
    expect((await client.postAuth(ApiConfig.logoutUrl)).success, true);
    client.dispose();
    api.dispose();
    DatabaseHelper.activateScope(null);
  });
}
