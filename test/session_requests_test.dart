import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile/core/database/database_helper.dart';
import 'package:mobile/services/api_service.dart';
import 'package:mobile/services/storage_service.dart';

class TokenStorage extends StorageService {
  Future<String?> token = Future.value('token-a');
  @override
  Future<String?> getAccessToken() => token;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('optional public catalog requests carry the active identity', () async {
    final storage = TokenStorage();
    DatabaseHelper.activateScope('company-a:user-a');
    final api = ApiService(
      storage,
      client: MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer token-a');
        return http.Response('[]', 200);
      }),
    );
    expect((await api.get('https://example.invalid/catalog')).success, isTrue);
  });

  test('a pending queue is never sent using the next account token', () async {
    final storage = TokenStorage();
    final token = Completer<String?>();
    storage.token = token.future;
    DatabaseHelper.activateScope('company-a:user-a');
    var calls = 0;
    final api = ApiService(
      storage,
      client: MockClient((request) async {
        calls++;
        return http.Response('{}', 200);
      }),
    );
    final pending = api.postAuth(
      'https://example.invalid/sync',
      {'operations': []},
      null,
      'company-a:user-a',
    );
    DatabaseHelper.activateScope('company-b:user-b');
    token.complete('token-b');
    expect((await pending).statusCode, 401);
    expect(calls, 0);
  });

  test('responses from the previous identity are discarded', () async {
    final response = Completer<http.Response>();
    final sent = Completer<void>();
    DatabaseHelper.activateScope('company-a:user-a');
    final api = ApiService(
      TokenStorage(),
      client: MockClient((request) {
        sent.complete();
        return response.future;
      }),
    );
    final pending = api.getAuth('https://example.invalid/wallet');
    await sent.future;
    DatabaseHelper.activateScope('company-b:user-b');
    response.complete(http.Response('{"saldo":100}', 200));
    expect((await pending).statusCode, 401);
  });
}
