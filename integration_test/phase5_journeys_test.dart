import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'package:mobile/main.dart' as app;
import 'package:mobile/config/routes.dart';
import 'package:mobile/screens/auth/login_screen.dart';
import 'package:mobile/screens/shop/catalog_screen.dart';
import 'package:mobile/screens/shop/product_detail_screen.dart';
import 'package:mobile/services/auth_service.dart';
import 'package:mobile/services/api_service.dart';
import 'package:mobile/services/storage_service.dart';
import 'package:mobile/services/cart_service.dart';
import 'package:mobile/services/reservation_service.dart';
import 'package:mobile/config/api_config.dart';
import 'package:mobile/services/sale_service.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Android real login catalog detail cart reserve cancel favorites wallet history profile logout',
    (tester) async {
      if (ApiConfig.baseUrl != 'http://10.0.2.2:58001') {
        throw StateError('Dedicated local phase5 API required');
      }
      // Repeatable synthetic funding; never a provider charge or stored token.
      final setupClient = http.Client();
      try {
        final login = await setupClient.post(
          Uri.parse(ApiConfig.loginUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': 'phase5-admin@example.com',
            'password': 'Phase5-Local-Only!',
          }),
        );
        expect(login.statusCode, 200);
        final token = jsonDecode(login.body)['access_token'];
        final credit = await setupClient.post(
          Uri.parse('${ApiConfig.apiUrl}/wallet/admin/topup-cash'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'user_email': 'phase5-cliente@example.com',
            'monto': 100,
            'client_operation_id': const Uuid().v4(),
            'notas': 'Preparación sintética de integración Android',
          }),
        );
        expect(credit.statusCode, 200);
      } finally {
        setupClient.close();
      }
      final completed = <String>[];
      Future<void> waitFor(Finder finder, {int seconds = 40}) async {
        for (var i = 0; i < seconds * 4; i++) {
          await tester.pump(const Duration(milliseconds: 250));
          if (finder.evaluate().isNotEmpty) {
            debugPrint(
              'PHASE5_ANDROID_FOUND=${finder.toString().split('\n').first}',
            );
            return;
          }
        }
        throw TestFailure('No aparece: $finder');
      }

      Future<void> tap(Finder finder) async {
        await waitFor(finder);
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();
        // Dismiss transient feedback before interacting with lower controls.
        if (find.byType(SnackBar).evaluate().isNotEmpty) {
          ScaffoldMessenger.maybeOf(tester.element(finder))
              ?.removeCurrentSnackBar();
          await tester.pumpAndSettle();
        }
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
        await waitFor(finder.hitTestable());
        await tester.tap(finder);
        await tester.pumpAndSettle(
          const Duration(milliseconds: 200),
          EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 25),
        );
      }

      Future<void> open(String route) async {
        final ctx = tester.element(find.byType(Navigator).first);
        Navigator.of(ctx).pushNamed(route);
        await tester.pumpAndSettle(
          const Duration(milliseconds: 200),
          EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 25),
        );
      }

      app.main();
      await waitFor(
        find.byWidgetPredicate((w) => w is LoginScreen || w is CatalogScreen),
      );
      if (find.byType(LoginScreen).evaluate().isEmpty) {
        final ctx = tester.element(find.byType(CatalogScreen).first);
        await ctx.read<AuthService>().logout();
        Navigator.of(ctx)
            .pushNamedAndRemoveUntil(AppRoutes.login, (_) => false);
        await tester.pumpAndSettle();
      }
      await waitFor(find.byType(TextFormField));
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'phase5-cliente@example.com',
      );
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'Phase5-Local-Only!',
      );
      await tap(
        find.widgetWithText(ElevatedButton, 'Ingresar a FashionStore QA'),
      );
      await waitFor(find.text('Camisa QA'));
      completed.add('login y catálogo desde API real');
      await tap(find.text('Camisa QA').first);
      await waitFor(find.byType(ProductDetailScreen));
      await waitFor(find.text('Añadir al Carrito'));
      await tap(find.text('Añadir al Carrito'));
      final ctx = tester.element(find.byType(ProductDetailScreen));
      final cart = ctx.read<CartService>();
      expect(cart.items.single.unitPrice, 75);
      completed.add('detalle → variante → carrito con precio de oferta');
      await open(AppRoutes.cart);
      await tap(find.text('Apartar con Reserva Click & Collect'));
      await waitFor(find.text('¡Reserva Creada!'));
      completed.add('reserva desde botón del carrito');
      // Verify persisted effect through the same authenticated production client.
      final authCtx = tester.element(find.byType(Navigator).first);
      final resService = ctx.read<ReservationService>();
      final reservations = await resService.getMyReservations();
      expect(reservations, isNotEmpty);
      expect(reservations.first.total, 75);
      expect(cart.isEmpty, true);
      // Close confirmation and show the real reservation list/detail.
      Navigator.of(authCtx).pop();
      await tester.pumpAndSettle();
      await open(AppRoutes.reservations);
      await waitFor(find.text(reservations.first.numeroReserva));
      await tap(find.widgetWithText(OutlinedButton, 'Cancelar').first);
      await tap(find.text('Sí, Cancelar'));
      expect((await resService.getMyReservations()).first.estado, 'CANCELADA');
      completed.add('reserva propia consultada y cancelada en servidor');
      // Return to the real detail screen and use its favorite/checkout controls.
      Navigator.of(authCtx).pop();
      await tester.pumpAndSettle();
      Navigator.of(authCtx).pop();
      await tester.pumpAndSettle();
      final addFavorite = find.byTooltip('Agregar a favoritos');
      if (addFavorite.evaluate().isNotEmpty) await tap(addFavorite);
      await open(AppRoutes.favorites);
      await waitFor(find.text('Camisa QA'));
      completed.add('favorito mediante botón y listado desde API real');
      Navigator.of(authCtx).pop();
      await tester.pumpAndSettle();
      await tap(find.text('Añadir al Carrito'));
      await open(AppRoutes.cart);
      await tap(find.text('Pagar con Billetera Virtual'));
      await tap(find.text('Autorizar Pago'));
      await waitFor(find.text('¡Compra Exitosa!'));
      final sales = await ctx.read<SaleService>().getMySales();
      expect(
        sales.any((s) => s.total == 75 && s.metodoPago == 'BILLETERA'),
        true,
      );
      expect(cart.isEmpty, true);
      completed.add('pago desde carrito → confirmación → venta persistida');
      Navigator.of(authCtx).pop();
      await tester.pumpAndSettle();
      final api = ctx.read<ApiService>();
      await open(AppRoutes.wallet);
      await waitFor(find.textContaining('Billetera').first);
      completed.add('billetera inicial y saldo autenticado');
      await open(AppRoutes.purchases);
      await waitFor(find.textContaining('Historial').first);
      completed.add('historial propio vacío o con compras');
      await open(AppRoutes.offlineSync);
      await waitFor(find.text('Sincronización Offline'));
      completed.add('cola propia consultable');
      await open(AppRoutes.home);
      await tap(find.text('Mi Perfil'));
      await tap(find.text('Editar Perfil'));
      final profileName =
          'Cliente QA Android ${DateTime.now().millisecondsSinceEpoch}';
      await tester.enterText(find.byType(TextFormField).first, profileName);
      await tap(find.text('Guardar Cambios'));
      final savedProfile = await api.getAuth(ApiConfig.profileUrl);
      expect(
        savedProfile.data['full_name'],
        profileName,
        reason: ctx.read<AuthService>().error,
      );
      await tap(find.text('Bandeja de Notificaciones'));
      await waitFor(find.text('Notificaciones'));
      if (find.text('Leer todas').evaluate().isNotEmpty) {
        await tap(find.text('Leer todas'));
      }
      completed.add(
        'perfil editado y bandeja de notificaciones desde pantalla',
      );
      Navigator.of(authCtx).pop();
      await tester.pumpAndSettle();
      final profile = await api.getAuth(ApiConfig.profileUrl);
      expect(profile.success, true);
      expect(profile.data['email'], 'phase5-cliente@example.com');
      expect(profile.data['full_name'], profileName);
      await tap(find.text('Cerrar Sesión').last);
      await tap(find.widgetWithText(ElevatedButton, 'Cerrar Sesión'));
      await waitFor(find.byType(LoginScreen));
      expect(await StorageService().getAccessToken(), isNull);
      expect(cart.isEmpty, true);
      completed.add('logout mediante botón revoca sesión y limpia carrito');
      await open(AppRoutes.register);
      await tap(find.byType(DropdownButtonFormField<String>));
      await tap(find.text('FashionStore QA').last);
      final email =
          'qa.android.${DateTime.now().millisecondsSinceEpoch}@example.com';
      for (final entry in [
        'Cliente Android QA',
        email,
        'OnlyTest123!',
        'OnlyTest123!',
      ].asMap().entries) {
        await tester.ensureVisible(find.byType(TextFormField).at(entry.key));
        await tester.enterText(
          find.byType(TextFormField).at(entry.key),
          entry.value,
        );
      }
      await tap(find.text('Crear cuenta'));
      await waitFor(find.text('Camisa QA'));
      final newCtx = tester.element(find.byType(CatalogScreen).first);
      expect(newCtx.read<AuthService>().currentUser!.email, email);
      await newCtx.read<AuthService>().logout();
      completed.add(
        'registro con selección explícita de empresa y nueva identidad',
      );
      binding.reportData = {'checks': completed};
      debugPrint('PHASE5_ANDROID_RESULT=${jsonEncode({'checks': completed})}');
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
