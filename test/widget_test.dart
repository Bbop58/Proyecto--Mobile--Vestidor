import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/user.dart';

void main() {
  group('User Model Tests', () {
    test('User.fromJson creates valid User object', () {
      final json = {
        'id': 'c56a4180-65aa-42ec-a945-5fd21dec0538',
        'email': 'test@example.com',
        'full_name': 'Test User',
        'is_active': true,
        'created_at': '2026-09-01T00:00:00',
      };

      final user = User.fromJson(json);

      expect(user.id, equals('c56a4180-65aa-42ec-a945-5fd21dec0538'));
      expect(user.email, equals('test@example.com'));
      expect(user.fullName, equals('Test User'));
      expect(user.isActive, isTrue);
      expect(user.createdAt, equals('2026-09-01T00:00:00'));
    });

    test('User.toJson serializes correctly', () {
      final user = User(
        id: '2',
        email: 'dev@example.com',
        fullName: 'Dev User',
        isActive: true,
        createdAt: '2026-09-02T00:00:00',
      );

      final json = user.toJson();

      expect(json['id'], equals('2'));
      expect(json['email'], equals('dev@example.com'));
      expect(json['full_name'], equals('Dev User'));
      expect(json['is_active'], isTrue);
    });

    test('User.copyWith updates fields correctly', () {
      final user = User(
        id: '1',
        email: 'old@example.com',
        fullName: 'Old Name',
        isActive: true,
        createdAt: '2026-09-01T00:00:00',
      );

      final updated = user.copyWith(fullName: 'New Name');

      expect(updated.id, equals('1'));
      expect(updated.email, equals('old@example.com'));
      expect(updated.fullName, equals('New Name'));
    });
  });
}

