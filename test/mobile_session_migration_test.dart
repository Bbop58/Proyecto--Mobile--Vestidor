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
  test(
    'a tombstone prevents migration from old keys after definitive revocation',
    () async {
      final storage = MemorySessionStorage()
        ..saved = SessionEnvelope(active: record())
        ..legacy = {
          'access_token': 'old-private-access',
          'refresh_token': 'old-private-refresh',
        };
      var refreshes = 0;
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/mobile/refresh')) {
          refreshes++;
          return http.Response(
            jsonEncode({
              'detail': {'code': 'MOBILE_SESSION_REVOKED'},
            }),
            401,
          );
        }
        expect(request.url.path.endsWith('/mobile/logout'), true);
        return http.Response('{}', 200);
      });
      final service = MobileSessionService(storage, client: client);
      await service.restore();
      expect(service.state, SessionState.reauthRequired);
      expect(storage.saved!.active, isNull);
      final restarted = MobileSessionService(storage, client: client);
      await restarted.restore();
      await restarted.flushPendingRevocations();
      expect(restarted.hasIdentity, false);
      expect(refreshes, 1);
      service.dispose();
      restarted.dispose();
      client.close();
    },
  );
  test('known contractual restrictions survive an offline restart without deleting identity', () async {
    final storage = MemorySessionStorage()
      ..saved = SessionEnvelope(active: record());
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'detail': {'code': 'MOBILE_SERVICE_RESTRICTED'},
        }),
        403,
      ),
    );
    final service = MobileSessionService(storage, client: client);
    await service.restore();
    expect(service.hasIdentity, true);
    expect(service.state, SessionState.restricted);
    expect(
      storage.saved!.active!.profile['subscription_capabilities']['offline'],
      false,
    );
    final offline = MockClient(
      (_) async => throw http.ClientException('offline'),
    );
    final restarted = MobileSessionService(storage, client: offline);
    await restarted.restore();
    expect(restarted.hasIdentity, true);
    expect(restarted.profile!['service_restricted'], true);
    expect(restarted.profile!['subscription_capabilities']['offline'], false);
    service.dispose();
    restarted.dispose();
    client.close();
    offline.close();
  });
  test('a late mobile exchange preserves the new account and queues the old credential', () async {
    final pending = Completer<http.Response>(), sent = Completer<void>();
    final storage = MemorySessionStorage();
    final client = MockClient((request) {
      if (request.url.path.endsWith('/mobile/session')) {
        sent.complete();
        return pending.future;
      }
      return Future.value(http.Response('{}', 200));
    });
    final service = MobileSessionService(storage, client: client);
    final previous = service.bootstrap(legacyAccessToken: 'legacy');
    await sent.future;
    await service.signOut();
    await service.establish(
      response(sid: sessionB, user: userB, company: companyB),
    );
    pending.complete(http.Response(jsonEncode(response()), 200));
    await previous;
    expect(service.identity!.userId, userB);
    expect(storage.saved!.active!.identity.userId, userB);
    expect(
      storage.saved!.pendingRevocations.any(
        (r) => r.kind == 'mobile' && r.credential == credential(sessionA),
      ),
      true,
    );
    service.dispose();
    client.close();
  });
  test('a refresh response cannot replace the next company session', () async {
    final pending = Completer<http.Response>(), sent = Completer<void>();
    final storage = MemorySessionStorage()
      ..saved = SessionEnvelope(active: record());
    final client = MockClient((request) {
      sent.complete();
      return pending.future;
    });
    final service = MobileSessionService(storage, client: client);
    final initial = service.restore();
    await sent.future;
    await service.establish(
      response(sid: sessionB, user: userB, company: companyB),
    );
    pending.complete(http.Response(jsonEncode(response()), 200));
    await initial;
    expect(service.identity!.scope, '$companyB:$userB');
    expect(storage.saved!.active!.identity.userId, userB);
    service.dispose();
    client.close();
  });
  test('legacy migration renews an expired access once then creates a persistent session', () async {
    final storage = MemorySessionStorage()
      ..legacy = {
        'access_token': access(expiry: 1),
        'refresh_token': 'synthetic-legacy-refresh',
      };
    final routes = <String>[];
    final client = MockClient((request) async {
      routes.add(request.url.path);
      if (request.url.path.endsWith('/auth/refresh')) {
        return http.Response(
          jsonEncode({
            'access_token': 'renewed-legacy',
            'refresh_token': 'rotated-legacy',
          }),
          200,
        );
      }
      if (request.url.path.endsWith('/mobile/session')) {
        expect(request.headers['Authorization'], 'Bearer renewed-legacy');
        return http.Response(jsonEncode(response()), 200);
      }
      return http.Response('{}', 200);
    });
    final service = MobileSessionService(storage, client: client);
    await service.restore();
    await service.flushPendingRevocations();
    expect(service.hasIdentity, true);
    expect(routes.where((p) => p.endsWith('/auth/refresh')).length, 1);
    expect(storage.legacy, isNull);
    expect(storage.saved!.active, isNotNull);
    service.dispose();
    client.close();
  });
  test(
    'offline legacy migration preserves keys and never invents a tenant',
    () async {
      final storage = MemorySessionStorage()
        ..legacy = {'refresh_token': 'synthetic-legacy-refresh'};
      final client = MockClient(
        (_) async => throw http.ClientException('offline'),
      );
      final service = MobileSessionService(storage, client: client);
      await service.restore();
      expect(service.hasIdentity, false);
      expect(service.awaitingLegacyConnection, true);
      expect(storage.legacy, isNotNull);
      expect(storage.saved, isNull);
      service.dispose();
      client.close();
    },
  );
  test('logout can retry a failed secure read instead of keeping a rejected future forever', () async {
    final storage = MemorySessionStorage()
      ..saved = SessionEnvelope(active: record())
      ..failReads = true;
    final client = MockClient((_) async => http.Response('{}', 200));
    final service = MobileSessionService(storage, client: client);
    await expectLater(
      service.signOut(),
      throwsA(isA<SessionStorageException>()),
    );
    expect(service.logoutNeedsRetry, true);
    storage.failReads = false;
    await service.signOut();
    expect(storage.saved!.active, isNull);
    expect(service.logoutNeedsRetry, false);
    service.dispose();
    client.close();
  });
  test(
    'redirects cannot forward the persistent credential to another host',
    () async {
      final storage = MemorySessionStorage()
        ..saved = SessionEnvelope(active: record());
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        expect(request.followRedirects, false);
        return http.Response(
          '',
          307,
          headers: {'location': 'https://foreign.invalid/steal'},
        );
      });
      final service = MobileSessionService(storage, client: client);
      await service.restore();
      expect(service.hasIdentity, true);
      expect(service.state, SessionState.offline);
      expect(calls, 1);
      service.dispose();
      client.close();
    },
  );
  for (final code in ['MOBILE_SESSION_REVOKED', 'MOBILE_SERVICE_RESTRICTED']) {
    test(
      'failed durable handling of $code is blocked and retried before offline restoration',
      () async {
        final storage = MemorySessionStorage();
        var reject = false;
        final client = MockClient(
          (_) async => reject
              ? http.Response(
                  jsonEncode({
                    'detail': {'code': code},
                  }),
                  code == 'MOBILE_SESSION_REVOKED' ? 401 : 403,
                )
              : http.Response(jsonEncode(response()), 200),
        );
        final service = MobileSessionService(storage, client: client);
        await service.establish(response());
        reject = true;
        storage.failWrites = true;
        await expectLater(
          service.accessToken(forceRefresh: true),
          throwsA(isA<SessionStorageException>()),
        );
        expect(service.state, SessionState.storageError);
        expect(service.hasIdentity, false);
        storage.failWrites = false;
        await service.restore(retry: true);
        if (code == 'MOBILE_SESSION_REVOKED') {
          expect(service.hasIdentity, false);
          expect(storage.saved!.active, isNull);
        } else {
          expect(service.state, SessionState.restricted);
          expect(
            storage
                .saved!
                .active!
                .profile['subscription_capabilities']['offline'],
            false,
          );
        }
        service.dispose();
        client.close();
      },
    );
  }
  test('platform profiles are rejected by the actual durable decoder', () {
    final data = response();
    (data['user'] as Map)['access_scope'] = 'PLATFORM';
    expect(() => MobileSessionRecord.fromJson(data), throwsFormatException);
  });
}
