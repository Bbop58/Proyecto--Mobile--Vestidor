import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:mobile/models/mobile_session.dart';
import 'package:mobile/services/storage_service.dart';

import 'support/mobile_sessions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  test('a failed durable write does not become a cached session', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'write') {
            throw PlatformException(code: 'write_failed');
          }
          return null;
        });
    final storage = StorageService();
    await expectLater(
      storage.writeSessionEnvelope(const SessionEnvelope()),
      throwsA(isA<SessionStorageException>()),
    );
    expect(await storage.readSessionEnvelope(), isNull);
  });
  test('a signed-out document survives a fresh storage instance', () async {
    final values = <String, String>{'access_token': 'synthetic-legacy-token'};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          final args = Map<String, dynamic>.from(call.arguments as Map);
          if (call.method == 'write') {
            values[args['key']] = args['value'];
            return null;
          }
          if (call.method == 'read') return values[args['key']];
          return null;
        });
    await StorageService().writeSessionEnvelope(const SessionEnvelope());
    final restored = await StorageService().readSessionEnvelope();
    expect(restored, isNotNull);
    expect(restored!.active, isNull);
  });
  test('corrupt secure data is not an absent session', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => '{broken');
    await expectLater(
      StorageService().readSessionEnvelope(),
      throwsA(isA<SessionStorageException>()),
    );
  });
  test(
    'a native write past its deadline cannot overwrite a later logout',
    () async {
      final values = <String, String>{};
      final started = Completer<void>(), gate = Completer<void>();
      var writes = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            final args = Map<String, dynamic>.from(call.arguments as Map);
            if (call.method == 'write') {
              writes++;
              if (writes == 1) {
                started.complete();
                await gate.future;
              }
              values[args['key']] = args['value'];
              return null;
            }
            if (call.method == 'read') return values[args['key']];
            return null;
          });
      final storage = StorageService(
        sessionTimeout: const Duration(milliseconds: 40),
      );
      final first = storage.writeSessionEnvelope(
        SessionEnvelope(active: record()),
      );
      final failed = expectLater(
        first,
        throwsA(isA<SessionStorageException>()),
      );
      await started.future;
      await failed;
      final closing = storage.writeSessionEnvelope(const SessionEnvelope());
      expect(writes, 1);
      gate.complete();
      await closing;
      expect(writes, 2);
      expect((await StorageService().readSessionEnvelope())!.active, isNull);
    },
  );
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );
}
