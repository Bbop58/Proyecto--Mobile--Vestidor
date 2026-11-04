import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/database/database_helper.dart';
import 'package:mobile/services/api_service.dart';
import 'package:mobile/services/storage_service.dart';
import 'package:mobile/services/chatbot_service.dart';

class _Api extends ApiService {
  _Api() : super(StorageService());
  final pending = Completer<ApiResponse>();
  Duration? lastTimeout;
  @override
  Future<ApiResponse> postAuth(
    String url, [
    Map<String, dynamic>? body,
    Duration? timeout,
    String? expectedScope,
  ]) {
    lastTimeout = timeout;
    return pending.future;
  }
}

void main() {
  test(
    'chat clears identity history and ignores old reply after account change',
    () async {
      DatabaseHelper.activateScope('a:user');
      final transport = _Api();
      final subject = ChatbotService(transport);
      final request = subject.sendMessage('mi saldo');
      expect(transport.lastTimeout, const Duration(seconds: 30));
      DatabaseHelper.activateScope('b:user');
      transport.pending.complete(
        ApiResponse(
          success: true,
          statusCode: 200,
          data: {'reply': 'PRIVATE A', 'tenant_name': 'A', 'tenant_slug': 'a'},
        ),
      );
      await request;
      expect(
        subject.messages.any(
          (m) => m.content.contains('PRIVATE A') || m.content == 'mi saldo',
        ),
        false,
      );
      subject.dispose();
      transport.dispose();
      DatabaseHelper.activateScope(null);
    },
  );
  test('unavailable AI does not invent funds or delivery tariffs', () async {
    DatabaseHelper.activateScope('a:user');
    final api = _Api(), chat = ChatbotService(api);
    final request = chat.sendMessage('saldo y delivery');
    api.pending.complete(
      ApiResponse(success: false, statusCode: 503, error: 'No disponible'),
    );
    await request;
    expect(chat.messages.last.content, contains('No pude consultar'));
    expect(chat.messages.last.content, isNot(contains('0.00 Bs.')));
    chat.dispose();
    api.dispose();
    DatabaseHelper.activateScope(null);
  });
}
