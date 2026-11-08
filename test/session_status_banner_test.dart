import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:mobile/core/database/database_helper.dart';
import 'package:mobile/core/services/connectivity_service.dart';
import 'package:mobile/core/services/offline_sync_service.dart';
import 'package:mobile/services/api_service.dart';
import 'package:mobile/services/auth_service.dart';
import 'package:mobile/services/mobile_session_service.dart';
import 'package:mobile/widgets/offline_connectivity_banner.dart';

import 'session_offline_lifecycle_test.dart' show QaConnection;
import 'support/mobile_sessions.dart';

class _QueueStatus extends ChangeNotifier implements OfflineSyncService {
  @override
  int get pendingCount => 0;
  @override
  bool get isSyncing => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'session banner distinguishes offline from unverified and wraps large text at 320px',
    (tester) async {
      final storage = MemorySessionStorage();
      final raw = MockClient(
        (_) async => throw http.ClientException('offline'),
      );
      final sessions = MobileSessionService(storage, client: raw);
      final api = ApiService(storage, sessions: sessions);
      final auth = AuthService(api, storage);
      final connection = QaConnection(), queue = _QueueStatus();
      await sessions.establish(response());
      await sessions.revalidate();
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthService>.value(value: auth),
            ChangeNotifierProvider<ConnectivityService>.value(
              value: connection,
            ),
            ChangeNotifierProvider<OfflineSyncService>.value(value: queue),
          ],
          child: MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2.5)),
              child: const Scaffold(
                body: Column(children: [OfflineConnectivityBanner()]),
              ),
            ),
          ),
        ),
      );
      expect(find.textContaining('Sin Internet:'), findsOneWidget);
      expect(tester.takeException(), isNull);
      connection.setOnline(true);
      await tester.pump();
      expect(find.textContaining('Sesión sin verificar'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      queue.dispose();
      connection.dispose();
      auth.dispose();
      api.dispose();
      sessions.dispose();
      raw.close();
      DatabaseHelper.activateScope(null);
    },
  );
}
