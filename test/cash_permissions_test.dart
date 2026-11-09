import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/user.dart';
import 'package:mobile/models/mobile_session.dart';

void main() {
  final base = <String, dynamic>{
    'id': 'person', 'tenant_id': 'company', 'email': 'test@example.com',
    'full_name': 'Test', 'is_active': true, 'access_scope': 'COMPANY',
    'subscription_capabilities': {'offline': true},
  };

  test('legacy profile has no cash permission', () {
    final user = User.fromJson(sessionProfile(base));
    expect(user.hasPermission('ventas.create'), isFalse);
  });

  test('validated permission survives mobile profile serialization', () {
    final raw = {...base, 'permissions': ['ventas.create', 'productos.list']};
    final profile = sessionProfile(raw);
    final user = User.fromJson(profile);
    expect(user.hasPermission('ventas.create'), isTrue);
    expect(User.fromJson(user.toJson()).hasPermission('ventas.create'), isTrue);
    expect(user.copyWith(fullName: 'Nuevo').hasPermission('ventas.create'), isTrue);
  });

  test('invalid permission payload is rejected', () {
    expect(() => sessionProfile({...base, 'permissions': ['ventas.create', 42]}), throwsFormatException);
    expect(() => sessionProfile({...base, 'permissions': 'ventas.create'}), throwsFormatException);
  });

}
