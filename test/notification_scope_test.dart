import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mobile/screens/notifications/notifications_screen.dart';
import 'package:mobile/core/database/database_helper.dart';
import 'package:mobile/services/api_service.dart';
import 'package:mobile/services/storage_service.dart';
import 'package:mobile/services/notification_service.dart';

class _Api extends ApiService {
  _Api() : super(StorageService());
  @override
  Future<ApiResponse> postAuth(
    String url, [
    Map<String, dynamic>? body,
    Duration? timeout,
    String? expectedScope,
  ]) async => ApiResponse(
    success: false,
    statusCode: 503,
    error: 'Servidor no disponible',
  );
  Completer<ApiResponse>? pending;
  bool fail = false;
  @override
  Future<ApiResponse> getAuth(String url) async =>
      pending?.future ??
      (fail
          ? ApiResponse(
              success: false,
              statusCode: 503,
              error: 'Servidor no disponible',
            )
          : ApiResponse(
              success: true,
              statusCode: 200,
              data: [
                {
                  'id': 'notification-a',
                  'title': 'Private A',
                  'message': 'Only A',
                  'is_read': false,
                },
              ],
            ));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'notifications screen shows retry on failure instead of empty inbox',
    (tester) async {
      DatabaseHelper.activateScope('notification_widget:user');
      final api = _Api()..fail = true;
      final service = NotificationService(api);
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: service,
          child: const MaterialApp(home: NotificationsScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('No tienes notificaciones'), findsNothing);
      expect(find.text('Servidor no disponible'), findsOneWidget);
      api.fail = false;
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(find.text('Private A'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      service.dispose();
      api.dispose();
      DatabaseHelper.activateScope(null);
    },
  );
  testWidgets('failed mark all action never announces success', (tester) async {
    DatabaseHelper.activateScope('notification_mark:user');
    final api = _Api();
    final service = NotificationService(api);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: service,
        child: const MaterialApp(home: NotificationsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Leer todas'));
    await tester.pumpAndSettle();
    expect(
      find.text('Todas las notificaciones marcadas como leídas'),
      findsNothing,
    );
    expect(service.unreadCount, 1);
    expect(
      find.text('No se pudieron marcar las notificaciones. Reintenta.'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    service.dispose();
    api.dispose();
    DatabaseHelper.activateScope(null);
  });
  test(
    'notification failure is recoverable and does not become an empty success',
    () async {
      DatabaseHelper.activateScope('notifications:user');
      final api = _Api()..fail = true;
      final service = NotificationService(api);
      await service.fetchNotifications();
      expect(service.errorMessage, isNotNull);
      expect(service.isLoading, false);
      api.fail = false;
      await service.fetchNotifications();
      expect(service.errorMessage, isNull);
      expect(service.notifications.length, 1);
      api.fail = true;
      await service.fetchNotifications();
      expect(service.errorMessage, isNotNull);
      expect(service.notifications.length, 1);
      DatabaseHelper.activateScope('other:user');
      expect(service.errorMessage, isNull);
      service.dispose();
      api.dispose();
      DatabaseHelper.activateScope(null);
    },
  );
  test('notification cache clears on account change and ignores late old identity response', () async {
    DatabaseHelper.activateScope('a:user');
    final api = _Api(), notifications = NotificationService(_Api());
    await notifications.fetchNotifications();
    expect(notifications.notifications.length, 1);
    DatabaseHelper.activateScope('b:user');
    expect(notifications.notifications, isEmpty);
    expect(notifications.unreadCount, 0);
    notifications.dispose();
    api.dispose();
    DatabaseHelper.activateScope('a:user');
    final lateApi = _Api()..pending = Completer<ApiResponse>();
    final late = NotificationService(lateApi);
    final request = late.fetchNotifications();
    DatabaseHelper.activateScope('b:user');
    lateApi.pending!.complete(
      ApiResponse(
        success: true,
        statusCode: 200,
        data: [
          {'id': 'old', 'title': 'Private A', 'is_read': false},
        ],
      ),
    );
    await request;
    expect(late.notifications, isEmpty);
    expect(late.unreadCount, 0);
    late.dispose();
    lateApi.dispose();
    DatabaseHelper.activateScope(null);
  });
}
