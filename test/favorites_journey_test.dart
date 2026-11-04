import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:mobile/core/database/database_helper.dart';
import 'package:mobile/core/services/connectivity_service.dart';
import 'package:mobile/services/api_service.dart';
import 'package:mobile/services/storage_service.dart';
import 'package:mobile/services/favorite_service.dart';

import 'channel_contracts_test.dart' show product;

class _Storage extends StorageService {
  @override
  Future<String?> getUserId() async => 'user';
}

class _Network extends ChangeNotifier implements ConnectivityService {
  bool online = false;
  @override
  bool get isOnline => online;
  @override
  bool get wasOffline => false;
  @override
  void clearReconnectedFlag() {}
}

class _Api extends ApiService {
  _Api() : super(_Storage());
  bool saved = false;
  bool fail = false;
  int posts = 0;
  @override
  Future<ApiResponse> getAuth(String url) async => ApiResponse(
    success: true,
    statusCode: 200,
    data: saved
        ? [
            {'product_id': 'product', 'producto': product().toJson()},
          ]
        : [],
  );
  @override
  Future<ApiResponse> postAuth(
    String url, [
    Map<String, dynamic>? body,
    Duration? timeout,
    String? expectedScope,
  ]) async {
    posts++;
    if (fail) {
      return ApiResponse(success: false, statusCode: 503, error: 'network');
    }
    saved = true;
    return ApiResponse(success: true, statusCode: 201, data: {});
  }

  @override
  Future<ApiResponse> deleteAuth(String url) async {
    saved = false;
    return ApiResponse(success: true, statusCode: 200, data: {});
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Api api;
  late _Network network;
  late FavoriteService favorites;
  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final dir = await Directory.systemTemp.createTemp(
      'fashionstore_favorites_',
    );
    await databaseFactory.setDatabasesPath(dir.path);
    DatabaseHelper.activateScope(
      'favorite-${DateTime.now().microsecondsSinceEpoch}:user',
    );
    api = _Api();
    network = _Network();
    favorites = FavoriteService(api, network, _Storage());
    await favorites.loadLocalFavorites();
  });
  tearDown(() {
    favorites.dispose();
    network.dispose();
    api.dispose();
    DatabaseHelper.activateScope(null);
  });
  test(
    'offline favorite addition survives reconnection and reaches server',
    () async {
      await favorites.toggleFavorite(product());
      expect(favorites.isFavorite('product'), true);
      network.online = true;
      await favorites.fetchFavorites();
      expect(api.saved, true);
      expect(favorites.isFavorite('product'), true);
    },
  );
  test('failed remote write stays pending instead of being erased by the remote snapshot', () async {
    network.online = true;
    api.fail = true;
    await favorites.toggleFavorite(product());
    await favorites.fetchFavorites();
    expect(favorites.isFavorite('product'), true);
    api.fail = false;
    await favorites.fetchFavorites();
    expect(api.saved, true);
    expect(favorites.count, 1);
  });
  test(
    'offline favorite removal is not resurrected by old server state',
    () async {
      api.saved = true;
      network.online = true;
      await favorites.fetchFavorites();
      expect(favorites.count, 1);
      network.online = false;
      await favorites.toggleFavorite(product());
      expect(favorites.count, 0);
      network.online = true;
      await favorites.fetchFavorites();
      expect(api.saved, false);
      expect(favorites.count, 0);
    },
  );
  test(
    'an old favorite acknowledgement cannot erase a newer desired state',
    () async {
      final db = DatabaseHelper.instance.forScope(DatabaseHelper.scope!);
      await db.queueFavoriteChange(
        'user',
        product().toJson(),
        true,
        'revision-one',
      );
      await db.queueFavoriteChange(
        'user',
        product().toJson(),
        false,
        'revision-two',
      );
      await db.acknowledgeFavoriteChange('product', 'revision-one');
      final rows = await db.pendingFavoriteChanges('user');
      expect(rows.single['revision'], 'revision-two');
      expect(rows.single['desired'], 0);
    },
  );
  test('favorite mutation and cached state roll back together if SQLite rejects the write', () async {
    final db = DatabaseHelper.instance.forScope(DatabaseHelper.scope!);
    final sqlite = await db.database;
    await sqlite.execute(
      "CREATE TRIGGER reject_favorite BEFORE INSERT ON local_favorites BEGIN SELECT RAISE(ABORT,'injected failure'); END",
    );
    await expectLater(
      db.queueFavoriteChange('user', product().toJson(), true, 'one'),
      throwsException,
    );
    expect(await db.pendingFavoriteChanges('user'), isEmpty);
    expect(await db.getLocalFavorites('user'), isEmpty);
  });
}
