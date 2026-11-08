import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile/models/mobile_session.dart';
import 'package:mobile/services/mobile_session_service.dart';

import 'support/mobile_sessions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final code in [0, 503]) {
    test(
      'restore preserves identity and credentials after transient $code',
      () async {
        final storage = MemorySessionStorage()
          ..saved = SessionEnvelope(active: record());
        final client = MockClient((_) async {
          if (code == 0) throw http.ClientException('synthetic');
          return http.Response('{}', 503);
        });
        final service = MobileSessionService(storage, client: client);
        await service.restore();
        expect(service.state, SessionState.offline);
        expect(service.hasIdentity, true);
        expect(storage.saved!.active!.sessionId, sessionA);
        expect(storage.writes, 0);
        service.dispose();
        client.close();
      },
    );
  }
  test(
    'refresh restores from an opaque credential even without saved access',
    () async {
      final raw = response()..remove('access_token');
      final storage = MemorySessionStorage()
        ..saved = SessionEnvelope(active: MobileSessionRecord.fromJson(raw));
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        expect(request.url.path.endsWith('/mobile/refresh'), true);
        expect(jsonDecode(request.body)['session_token'], credential(sessionA));
        return http.Response(jsonEncode(response()), 200);
      });
      final service = MobileSessionService(storage, client: client);
      await Future.wait([service.restore(), service.restore()]);
      expect(service.state, SessionState.online);
      expect(calls, 1);
      expect(service.currentAccessToken, isNotNull);
      service.dispose();
      client.close();
    },
  );
  test(
    'manual offline logout is durable and is not restored after restart',
    () async {
      final storage = MemorySessionStorage();
      final client = MockClient(
        (_) async => throw http.ClientException('offline'),
      );
      final service = MobileSessionService(storage, client: client);
      await service.establish(response());
      await service.signOut();
      await service.flushPendingRevocations();
      expect(storage.saved!.active, isNull);
      expect(storage.saved!.pendingRevocations.length, 1);
      final restarted = MobileSessionService(storage, client: client);
      await restarted.restore();
      expect(restarted.hasIdentity, false);
      expect(restarted.state, SessionState.signedOut);
      service.dispose();
      restarted.dispose();
      client.close();
    },
  );
  test(
    'failed logout write blocks access and exposes an explicit retry',
    () async {
      final storage = MemorySessionStorage();
      final client = MockClient((_) async => http.Response('{}', 200));
      final service = MobileSessionService(storage, client: client);
      await service.establish(response());
      storage.failWrites = true;
      await expectLater(
        service.signOut(),
        throwsA(isA<SessionStorageException>()),
      );
      expect(service.hasIdentity, false);
      expect(service.logoutNeedsRetry, true);
      expect(storage.saved!.active, isNotNull);
      storage.failWrites = false;
      await service.signOut();
      expect(storage.saved!.active, isNull);
      expect(service.logoutNeedsRetry, false);
      service.dispose();
      client.close();
    },
  );
  test('a late refresh cannot reactivate a manually closed session', () async {
    final pending = Completer<http.Response>(), sent = Completer<void>();
    final storage = MemorySessionStorage()
      ..saved = SessionEnvelope(active: record());
    final client = MockClient((request) {
      if (request.url.path.endsWith('/mobile/refresh')) {
        sent.complete();
        return pending.future;
      }
      return Future.value(http.Response('{}', 200));
    });
    final service = MobileSessionService(storage, client: client);
    final restoring = service.restore();
    await sent.future;
    await service.signOut();
    pending.complete(http.Response(jsonEncode(response()), 200));
    await restoring;
    expect(service.hasIdentity, false);
    expect(storage.saved!.active, isNull);
    service.dispose();
    client.close();
  });
  test(
    'native write in flight followed by logout ends in a signed-out document',
    () async {
      final gate = Completer<void>();
      final storage = MemorySessionStorage()..delayWrite = gate.future;
      final client = MockClient((_) async => http.Response('{}', 200));
      final service = MobileSessionService(storage, client: client);
      final establishing = service.establish(response());
      await Future<void>.delayed(Duration.zero);
      final closing = service.signOut();
      gate.complete();
      await establishing;
      await closing;
      expect(service.hasIdentity, false);
      expect(storage.saved!.active, isNull);
      service.dispose();
      client.close();
    },
  );
  test(
    'a response from another company cannot replace the stored identity',
    () async {
      final storage = MemorySessionStorage()
        ..saved = SessionEnvelope(active: record());
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode(response(sid: sessionB, user: userB, company: companyB)),
          200,
        ),
      );
      final service = MobileSessionService(storage, client: client);
      await service.restore();
      expect(service.identity!.scope, '$companyA:$userA');
      expect(storage.writes, 0);
      expect(service.state, SessionState.offline);
      service.dispose();
      client.close();
    },
  );
}
