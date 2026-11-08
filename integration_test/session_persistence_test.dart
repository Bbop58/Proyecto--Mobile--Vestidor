import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:mobile/main.dart' as app;
import 'package:mobile/services/api_service.dart';
import 'package:mobile/services/auth_service.dart';
import 'package:mobile/services/storage_service.dart';
import 'package:mobile/services/wallet_service.dart';
import 'package:mobile/core/database/database_helper.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'SM4 native secure storage and real local API preserve both commercial identities',
    (tester) async {
      const emailA = String.fromEnvironment('SM4_EMAIL_A');
      const passwordA = String.fromEnvironment('SM4_PASSWORD_A');
      const tenantA = String.fromEnvironment('SM4_TENANT_A');
      const emailB = String.fromEnvironment('SM4_EMAIL_B');
      const passwordB = String.fromEnvironment('SM4_PASSWORD_B');
      const tenantB = String.fromEnvironment('SM4_TENANT_B');
      expect(
        [
          emailA,
          passwordA,
          tenantA,
          emailB,
          passwordB,
          tenantB,
        ].every((v) => v.isNotEmpty),
        true,
        reason: 'Supply the private local QA file, never real accounts or secrets in source',
      );
      expect(
        const String.fromEnvironment('API_URL'),
        'http://10.0.2.2:58012',
        reason: 'Native acceptance is restricted to the owned local API',
      );
      final watch = Stopwatch()..start();
      try {
        final raw = await const FlutterSecureStorage()
            .read(key: StorageService.sessionEnvelopeKey)
            .timeout(const Duration(seconds: 60));
        // Print only shape/timing; never the secure document or any credential.
        bool validShape;
        try {
          validShape = raw == null || jsonDecode(raw) is Map;
        } catch (_) {
          validShape = false;
        }
        debugPrint(
          'SM4 native read: elapsed_ms=${watch.elapsedMilliseconds}, present=${raw != null}, json_map=$validShape',
        );
      } on PlatformException {
        fail('Native secure storage could not be read');
      }
      await tester.pumpWidget(const app.MyApp());
      await tester.pump();
      final context = tester.element(find.byType(app.AuthWrapper).first);
      final auth = context.read<AuthService>();
      final api = context.read<ApiService>();
      final wallet = context.read<WalletService>();
      for (var n = 0; n < 300 && auth.isLoading; n++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(auth.isLoading, false);
      for (var n = 0; n < 3 && auth.sessionRecoveryNeeded; n++) {
        await auth.retrySession();
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(auth.sessionRecoveryNeeded, false, reason: auth.error);
      for (final account in [
        (emailA, passwordA, tenantA),
        (emailB, passwordB, tenantB),
        (emailA, passwordA, tenantA),
      ]) {
        expect(await auth.logout(), true, reason: auth.error);
        expect(
          await auth.login(email: account.$1, password: account.$2),
          true,
          reason: auth.error ?? 'Local QA login must succeed',
        );
        await tester.pump();
        expect(auth.isAuthenticated, true);
        expect(auth.currentUser!.tenantId, account.$3);
        expect(DatabaseHelper.scope, '${account.$3}:${auth.currentUser!.id}');
        final saved = await StorageService().readSessionEnvelope();
        expect(saved!.active!.identity.tenantId, account.$3);
        expect(saved.active!.profile['email'], account.$1);
        final credential = saved.active!.sessionToken;
        await api.sessions.accessToken(forceRefresh: true);
        final renewed = await StorageService().readSessionEnvelope();
        expect(
          renewed!.active!.sessionToken == credential,
          true,
          reason: 'Opaque credential must remain stable; values are private',
        );
        expect(
          renewed.active!.identity.sessionId,
          saved.active!.identity.sessionId,
        );
        await wallet.fetchWallet();
        expect(wallet.saldo, 100);
        expect(wallet.wallet!.userId, auth.currentUser!.id);
      }
      await tester.pump(const Duration(milliseconds: 200));
      expect(auth.currentUser!.tenantId, tenantA);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
