import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/main.dart' as app;

void main() {
  testWidgets('initial app frame survives unavailable native notifications', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    try {
      app.main();
      await tester.pump();
      expect(find.byType(app.MyApp), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });
}
