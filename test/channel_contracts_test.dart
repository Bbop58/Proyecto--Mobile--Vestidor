import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/database/database_helper.dart';
import 'package:mobile/services/cart_service.dart';
import 'package:mobile/services/sale_service.dart';
import 'package:mobile/services/reservation_service.dart';
import 'package:mobile/services/inventory_service.dart';
import 'package:mobile/services/category_service.dart';
import 'package:mobile/services/season_service.dart';
import 'package:mobile/services/api_service.dart';
import 'package:mobile/services/storage_service.dart';
import 'package:mobile/models/product.dart';
import 'package:mobile/models/product_variant.dart';

class _FailedApi extends ApiService {
  _FailedApi() : super(StorageService());
  @override
  Future<ApiResponse> getAuth(String url) async => ApiResponse(
    success: false,
    statusCode: 503,
    error: 'Servicio temporalmente no disponible',
  );
}

Product product() => Product.fromJson({
  'id': 'product',
  'nombre': 'Camisa',
  'precio_base': '100.00',
  'precio_oferta': '70.00',
  'en_oferta': true,
  'activo': true,
});
ProductVariant variant() => ProductVariant.fromJson({
  'id': 'variant',
  'producto_id': 'product',
  'talla': 'M',
  'color': 'Azul',
  'sku': 'SKU',
  'precio_extra': '5.00',
  'activo': true,
});
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => DatabaseHelper.activateScope(null));
  test('cart uses the offer plus variant surcharge quoted by the server', () {
    final cart = CartService();
    cart.addItem(product(), variant(), quantity: 2);
    expect(cart.items.single.unitPrice, 75);
    expect(cart.total, 150);
    cart.dispose();
  });
  test('cart is cleared when account or company changes', () {
    DatabaseHelper.activateScope('company-a:user-a');
    final cart = CartService();
    cart.addItem(product(), variant());
    DatabaseHelper.activateScope('company-b:user-b');
    expect(cart.isEmpty, true);
    expect(cart.selectedBranch, isNull);
    cart.dispose();
  });
  test('cart cannot accept negative or mismatched variant quantities', () {
    final cart = CartService();
    expect(
      () => cart.addItem(product(), variant(), quantity: -1),
      throwsArgumentError,
    );
    final wrong = ProductVariant.fromJson({
      'id': 'other',
      'producto_id': 'foreign',
      'precio_extra': 0,
    });
    expect(() => cart.addItem(product(), wrong), throwsArgumentError);
    expect(cart.isEmpty, true);
    cart.dispose();
  });
  test(
    'purchase history does not disguise server failure as an empty history',
    () async {
      await expectLater(
        SaleService(_FailedApi()).getMySales(),
        throwsException,
      );
    },
  );
  test(
    'reservations do not disguise server failure as an empty history',
    () async {
      await expectLater(
        ReservationService(_FailedApi()).getMyReservations(),
        throwsException,
      );
    },
  );
  test(
    'availability does not disguise server failure as out of stock',
    () async {
      await expectLater(
        InventoryService(_FailedApi())
            .getProductAvailability(productoId: 'product'),
        throwsException,
      );
    },
  );
  test(
    'category errors remain distinguishable from an empty category list',
    () async {
      await expectLater(
        CategoryService(_FailedApi()).getCategories(),
        throwsException,
      );
    },
  );
  test(
    'season errors remain distinguishable from an empty season list',
    () async {
      await expectLater(
        SeasonService(_FailedApi()).getSeasons(),
        throwsException,
      );
    },
  );
}
