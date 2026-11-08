import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile/core/database/database_helper.dart';
import 'package:mobile/services/api_service.dart';
import 'package:mobile/services/auth_service.dart';
import 'package:mobile/services/mobile_session_service.dart';

import 'support/mobile_sessions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => DatabaseHelper.activateScope(null));
  test(
    'login publishes identity only after the persistent document is written',
    () async {
      final gate = Completer<void>();
      final storage = MemorySessionStorage()..delayWrite = gate.future;
      final client = MockClient(
        (request) async => http.Response(
          jsonEncode(
            request.url.path.endsWith('/mobile/session')
                ? response()
                : request.url.path.endsWith('/login')
                ? {
                    'access_token': 'legacy',
                    'refresh_token': 'legacy-refresh',
                    'user': response()['user'],
                  }
                : {},
          ),
          200,
        ),
      );
      final sessions = MobileSessionService(storage, client: client);
      final api = ApiService(storage, client: client, sessions: sessions);
      final auth = AuthService(api, storage);
      final login = auth.login(
        email: 'qa@example.com',
        password: 'SyntheticOnly123!',
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(auth.isAuthenticated, false);
      expect(DatabaseHelper.scope, isNull);
      gate.complete();
      expect(await login, true);
      expect(auth.currentUser!.id, userA);
      expect(DatabaseHelper.scope, '$companyA:$userA');
      await sessions.flushPendingRevocations();
      auth.dispose();
      api.dispose();
      sessions.dispose();
    },
  );
  test(
    'failed persistent login storage is visible and never authenticated',
    () async {
      final storage = MemorySessionStorage()..failWrites = true;
      final client = MockClient(
        (request) async => http.Response(
          jsonEncode(
            request.url.path.endsWith('/login')
                ? {'access_token': 'legacy', 'user': response()['user']}
                : response(),
          ),
          200,
        ),
      );
      final sessions = MobileSessionService(storage, client: client);
      final api = ApiService(storage, client: client, sessions: sessions);
      final auth = AuthService(api, storage);
      expect(
        await auth.login(
          email: 'qa@example.com',
          password: 'SyntheticOnly123!',
        ),
        false,
      );
      expect(auth.isAuthenticated, false);
      expect(auth.sessionRecoveryNeeded, true);
      expect(storage.saved, isNull);
      auth.dispose();
      api.dispose();
      sessions.dispose();
    },
  );
  test(
    'created registration is reported honestly when the mobile exchange fails',
    () async {
      var registrations = 0;
      final storage = MemorySessionStorage();
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/register')) {
          registrations++;
          return http.Response(
            jsonEncode({'access_token': 'legacy', 'user': response()['user']}),
            201,
          );
        }
        return http.Response('{}', 503);
      });
      final sessions = MobileSessionService(storage, client: client);
      final api = ApiService(storage, client: client, sessions: sessions);
      final auth = AuthService(api, storage);
      expect(
        await auth.register(
          email: 'qa@example.com',
          password: 'SyntheticOnly123!',
          fullName: 'QA',
          tenantId: companyA,
        ),
        false,
      );
      expect(registrations, 1);
      expect(auth.error, contains('Cuenta creada'));
      expect(auth.isAuthenticated, false);
      auth.dispose();
      api.dispose();
      sessions.dispose();
    },
  );
}
