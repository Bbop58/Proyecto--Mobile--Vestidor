import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile/main.dart' as app;
import 'package:mobile/config/api_config.dart';
import 'package:mobile/core/database/database_helper.dart';
import 'package:mobile/core/services/connectivity_service.dart';
import 'package:mobile/core/services/offline_authorization_service.dart';
import 'package:mobile/core/services/offline_sync_service.dart';
import 'package:mobile/services/api_service.dart';
import 'package:mobile/services/auth_service.dart';
import 'package:mobile/services/branch_service.dart';
import 'package:mobile/services/cash_sale_service.dart';
import 'package:mobile/services/inventory_service.dart';
import 'package:mobile/services/product_service.dart';
import 'package:mobile/screens/sales/cash_sale_screen.dart';
import 'package:provider/provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('E4 cash sale survives native process restart and syncs once', (tester) async {
    const stage = String.fromEnvironment('E4_STAGE');
    const email = String.fromEnvironment('E4_EMAIL');
    const password = String.fromEnvironment('E4_PASSWORD');
    const requestId = String.fromEnvironment('E4_REQUEST');
    const apiUrl = String.fromEnvironment('API_URL');
    expect(apiUrl == 'http://10.0.2.2:58012' ||
        apiUrl == 'https://proyecto-backend-vestidor-production.up.railway.app', true);
    expect(['prepare', 'offline', 'sync'].contains(stage), true);
    expect(email.isNotEmpty && password.isNotEmpty && requestId.isNotEmpty, true);

    await tester.pumpWidget(const app.MyApp());
    await tester.pump();
    final context = tester.element(find.byType(app.AuthWrapper).first);
    final auth = context.read<AuthService>();
    for (var i = 0; i < 400 && auth.isLoading; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(auth.isLoading, false);
    for (var i = 0; i < 3 && auth.sessionRecoveryNeeded; i++) {
      await auth.retrySession();
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(auth.sessionRecoveryNeeded, false, reason: auth.error);
    final api = context.read<ApiService>();
    if (stage == 'prepare') {
      if (auth.isAuthenticated) expect(await auth.logout(), true);
      expect(await auth.login(email: email, password: password), true,
          reason: auth.error);
      await tester.pump();
      final user = auth.currentUser!;
      expect(CashSaleService.eligible(user), true);
      final branches = context.read<BranchService>();
      final branch = (await branches.getBranches()).first;
      final cash = CashSaleService(
        api: api, branches: branches,
        products: context.read<ProductService>(),
        inventory: context.read<InventoryService>(),
        authorizations: OfflineAuthorizationService(api),
      );
      final snapshot = await cash.prepare(branchId: branch.id, user: user);
      expect(snapshot.isValid, true);
      expect(snapshot.availability, isNotEmpty);
      expect((await DatabaseHelper.instance.forScope(DatabaseHelper.scope!)
          .listCashSnapshots()), isNotEmpty);
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => const CashSaleScreen(),
      ));
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Caja móvil'), findsOneWidget);
      expect(find.textContaining('Preparada hasta'), findsOneWidget);
    } else {
      expect(auth.isAuthenticated, true, reason: auth.error);
      final user = auth.currentUser!;
      expect(user.email, email);
      final db = DatabaseHelper.instance.forScope(DatabaseHelper.scope!);
      final snapshot = (await db.listCashSnapshots()).first;
      final branch = snapshot['branch_id'] as String;
      final cash = CashSaleService(
        api: api, branches: context.read<BranchService>(),
        products: context.read<ProductService>(),
        inventory: context.read<InventoryService>(),
        authorizations: OfflineAuthorizationService(api),
      );
      final prepared = await cash.loadPrepared(branch);
      expect(prepared, isNotNull);
      final sync = context.read<OfflineSyncService>();
      if (stage == 'offline') {
        final item = prepared!.availability.first;
        final price = ((item['precio'] as num).toDouble() * 100).round();
        final operationId = await cash.saveDraft(
          user: user, branchId: branch, localRequestId: requestId,
          items: [{'variante_id': item['variante_id'],
            'cantidad': 1, 'precio_unitario': item['precio']}],
          totalCents: price, receivedCents: price + 1000,
        );
        expect(operationId, isNotEmpty);
        final pending = await db.getPendingOperations();
        expect(pending.where((row) => row['client_operation_id'] == operationId).length, 1);
      } else {
        final pending = await db.getPendingOperations();
        expect(pending.length, 1);
        final connectivity = context.read<ConnectivityService>();
        for (var i = 0; i < 100 && !connectivity.isOnline; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(connectivity.isOnline, true, reason: 'Android connectivity not ready');
        for (var i = 0; i < 100 && sync.isSyncing; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        final sent = await sync.syncBatchNow(force: true);
        // A failed send must retain the operation; include the service's safe
        // status in the test failure without logging any token or payload.
        expect(sent, true, reason: sync.lastError ?? 'Sync did not run');
        final rows = await db.getAllOperations();
        final confirmed = rows.where((row) => row['client_operation_id'] ==
            pending.first['client_operation_id']).toList();
        expect(confirmed.length, 1);
        expect(confirmed.single['local_status'], 'CONFIRMADA');
        expect(confirmed.single['server_receipt'], isNotNull);
        expect(confirmed.single['server_entity_id'], isNotNull);
        final central = await api.get('${ApiConfig.apiUrl}/sync/operations/'
            '${pending.first['client_operation_id']}');
        expect(central.success, true, reason: central.error);
        expect(central.data['status'], 'CONFIRMADA');
        expect(central.data['server_entity_id'],
            confirmed.single['server_entity_id']);
        expect(central.data['receipt_number'],
            confirmed.single['server_receipt']);
        expect(await db.getPendingCount(), 0);
        expect(await sync.syncBatchNow(force: true), true);
        expect(await db.getPendingCount(), 0);
      }
    }
  }, timeout: const Timeout(Duration(minutes: 8)));
}
