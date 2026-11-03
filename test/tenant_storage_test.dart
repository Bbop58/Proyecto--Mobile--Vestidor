import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:mobile/core/database/database_helper.dart';
import 'package:mobile/models/user.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('SQLite preserves queues per company and account including an in-flight owner', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final directory = await Directory.systemTemp.createTemp(
      'fashionstore_phase1_',
    );
    await databaseFactory.setDatabasesPath(directory.path);
    final helper = DatabaseHelper.instance;
    DatabaseHelper.activateScope('company-a:user-a');
    final owned = helper.forScope('company-a:user-a');
    Map<String, dynamic> operation(String id) => {
      'client_operation_id': id,
      'operation_type': 'VENTA_CONTADO_OFFLINE',
      'sucursal_id': 'branch-a',
      'fecha_local': '2026-11-03T00:00:00Z',
      'monto_total': 10,
      'items_json': '[]',
      'local_status': 'LOCAL_PENDIENTE',
      'created_at': '2026-11-03',
    };
    await helper.insertPendingOperation(operation('first'));
    DatabaseHelper.activateScope('company-b:user-b');
    expect(await helper.getPendingCount(), 0);
    await owned.insertPendingOperation(operation('in-flight-a'));
    expect(await helper.getPendingCount(), 0);
    DatabaseHelper.activateScope('company-a:user-a');
    expect(await helper.getPendingCount(), 2);
    DatabaseHelper.activateScope(null);
    expect(await helper.getPendingCount(), 0);
    await expectLater(
      helper.insertPendingOperation(operation('anonymous')),
      throwsStateError,
    );
    // Named disposable test directory is retained; no application database is removed.
  });

  test(
    'user profile carries immutable company through serialization and edits',
    () {
      final user = User.fromJson({
        'id': 'a',
        'tenant_id': 'company-a',
        'full_name': 'Customer A',
      });
      expect(user.tenantId, 'company-a');
      expect(
        user.copyWith(fullName: 'Edited').toJson()['tenant_id'],
        'company-a',
      );
    },
  );
}
