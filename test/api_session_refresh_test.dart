import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile/config/api_config.dart';
import 'package:mobile/core/database/database_helper.dart';
import 'package:mobile/services/api_service.dart';
import 'package:mobile/services/mobile_session_service.dart';

import 'support/mobile_sessions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => DatabaseHelper.activateScope(null));
  test(
    'ten parallel GETs share one renewal after their rejected token',
    () async {
      var renewals = 0;
      final gate = Completer<void>();
      final raw = MockClient((request) async {
        renewals++;
        await gate.future;
        return http.Response(jsonEncode(response(signature: 'new')), 200);
      });
      final storage = MemorySessionStorage();
      final sessions = MobileSessionService(storage, client: raw);
      await sessions.establish(response(signature: 'old'));
      DatabaseHelper.activateScope(sessions.identity!.scope);
      var calls = 0;
      final business = MockClient((request) async {
        calls++;
        return request.headers['Authorization']!.endsWith('.old')
            ? http.Response('{}', 401)
            : http.Response('{}', 200);
      });
      final api = ApiService(storage, client: business, sessions: sessions);
      final requests = List.generate(
        10,
        (_) => api.getAuth('${ApiConfig.apiUrl}/qa'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      gate.complete();
      expect((await Future.wait(requests)).every((r) => r.success), true);
      expect(renewals, 1);
      expect(calls, 20);
      api.dispose();
      sessions.dispose();
      raw.close();
    },
  );
  test(
    'a payment POST is not replayed when the access token is renewed',
    () async {
      var renewals = 0;
      final raw = MockClient((_) async {
        renewals++;
        return http.Response(jsonEncode(response(signature: 'new')), 200);
      });
      final storage = MemorySessionStorage();
      final sessions = MobileSessionService(storage, client: raw);
      await sessions.establish(response());
      DatabaseHelper.activateScope(sessions.identity!.scope);
      var payments = 0;
      final business = MockClient((_) async {
        payments++;
        return http.Response('{}', 401);
      });
      final api = ApiService(storage, client: business, sessions: sessions);
      final result = await api.postAuth('${ApiConfig.apiUrl}/payments/qa', {
        'amount': 1,
      });
      expect(result.success, false);
      expect(payments, 1);
      expect(renewals, 1);
      expect(result.error, contains('Vuelve a intentar'));
      api.dispose();
      sessions.dispose();
      raw.close();
    },
  );
  test('foreign origins receive no session credentials or requests', () async {
    final storage = MemorySessionStorage();
    final sessions = MobileSessionService(
      storage,
      client: MockClient((_) async => http.Response('{}', 200)),
    );
    await sessions.establish(response());
    DatabaseHelper.activateScope(sessions.identity!.scope);
    var calls = 0;
    final api = ApiService(
      storage,
      sessions: sessions,
      client: MockClient((_) async {
        calls++;
        return http.Response('{}', 200);
      }),
    );
    expect((await api.getAuth('https://foreign.invalid/api')).success, false);
    expect(calls, 0);
    api.dispose();
    sessions.dispose();
  });
  test(
    'proactive renewal happens before a request can send expired access',
    () async {
      final storage = MemorySessionStorage();
      var renewals = 0;
      final raw = MockClient((_) async {
        renewals++;
        return http.Response(jsonEncode(response(signature: 'renewed')), 200);
      });
      final sessions = MobileSessionService(storage, client: raw);
      await sessions.establish(response(expiry: 1));
      DatabaseHelper.activateScope(sessions.identity!.scope);
      final api = ApiService(
        storage,
        sessions: sessions,
        client: MockClient((r) async {
          expect(r.headers['Authorization']!.endsWith('.renewed'), true);
          return http.Response('{}', 200);
        }),
      );
      expect((await api.getAuth('${ApiConfig.apiUrl}/qa')).success, true);
      expect(renewals, 1);
      api.dispose();
      sessions.dispose();
      raw.close();
    },
  );
  test('a previous session response is discarded even for the same company and user', () async {
    final storage = MemorySessionStorage();
    final raw = MockClient((_) async => http.Response('{}', 200));
    final sessions = MobileSessionService(storage, client: raw);
    await sessions.establish(response());
    DatabaseHelper.activateScope(sessions.identity!.scope);
    final sent = Completer<void>(), pending = Completer<http.Response>();
    final api = ApiService(
      storage,
      sessions: sessions,
      client: MockClient((_) {
        sent.complete();
        return pending.future;
      }),
    );
    final request = api.getAuth('${ApiConfig.apiUrl}/qa');
    await sent.future;
    await sessions.establish(response(sid: sessionB));
    pending.complete(http.Response('{"private":"old-session"}', 200));
    final result = await request;
    expect(result.success, false);
    expect(result.data, isNull);
    expect(result.error, 'La sesión cambió');
    api.dispose();
    sessions.dispose();
    raw.close();
  });
  test(
    'a staggered 401 uses an already renewed token without another renewal',
    () async {
      final storage = MemorySessionStorage();
      var renewals = 0;
      final raw = MockClient((_) async {
        renewals++;
        return http.Response(jsonEncode(response(signature: 'new')), 200);
      });
      final sessions = MobileSessionService(storage, client: raw);
      await sessions.establish(response(signature: 'old'));
      DatabaseHelper.activateScope(sessions.identity!.scope);
      var oldCalls = 0;
      final late = Completer<http.Response>(), bothSent = Completer<void>();
      final api = ApiService(
        storage,
        sessions: sessions,
        client: MockClient((r) async {
          if (r.headers['Authorization']!.endsWith('.new')) {
            return http.Response('{}', 200);
          }
          oldCalls++;
          if (oldCalls == 2) {
            bothSent.complete();
            return late.future;
          }
          await bothSent.future;
          return http.Response('{}', 401);
        }),
      );
      final first = api.getAuth('${ApiConfig.apiUrl}/qa');
      final second = api.getAuth('${ApiConfig.apiUrl}/qa');
      expect((await first).success, true);
      late.complete(http.Response('{}', 401));
      expect((await second).success, true);
      expect(renewals, 1);
      api.dispose();
      sessions.dispose();
      raw.close();
    },
  );
}
