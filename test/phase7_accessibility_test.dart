import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/config/theme.dart';
import 'package:mobile/models/product.dart';
import 'package:mobile/widgets/shop_product_tile.dart';
import 'package:mobile/widgets/purchase_summary_bar.dart';

double contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return (x > y ? x + 0.05 : y + 0.05) / (x > y ? y + 0.05 : x + 0.05);
}

void main() {
  test(
    'supporting text and primary labels meet readable contrast in both modes',
    () {
      expect(
        contrast(AppTheme.lightTextMuted, AppTheme.lightCard),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrast(AppTheme.darkTextMuted, AppTheme.darkCard),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrast(
          AppTheme.darkTheme.colorScheme.primary,
          AppTheme.darkTheme.colorScheme.onPrimary,
        ),
        greaterThanOrEqualTo(4.5),
      );
    },
  );
  for (final width in [320.0, 375.0, 768.0]) {
    testWidgets(
      'price, product and purchase stay usable at width $width with 200% text',
      (tester) async {
        tester.view.resetPhysicalSize();
        tester.view.physicalSize = Size(width, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var opened = false, favorite = false, added = false;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(2)),
              child: child!,
            ),
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: width - 32,
                  height: 650,
                  child: ShopProductTile(
                    product: Product(
                      id: 'qa',
                      codigo: 'QA',
                      nombre: 'Camisa de vestir con cuello italiano',
                      precioBase: 12345.67,
                      precioOferta: 9999.99,
                      enOferta: true,
                      categoriaNombre: 'Camisas de vestir',
                      activo: true,
                    ),
                    isFavorite: false,
                    onOpen: () => opened = true,
                    onFavorite: () => favorite = true,
                  ),
                ),
              ),
              bottomNavigationBar: PurchaseSummaryBar(
                total: 19999.98,
                onAdd: () => added = true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Bs. 9999.99'));
        expect(opened, isTrue);
        await tester.tap(find.byTooltip('Añadir a favoritos'));
        expect(favorite, isTrue);
        expect(
          tester.getSize(find.byType(IconButton)).width,
          greaterThanOrEqualTo(48),
        );
        await tester.tap(find.text('Añadir al Carrito'));
        expect(added, isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
