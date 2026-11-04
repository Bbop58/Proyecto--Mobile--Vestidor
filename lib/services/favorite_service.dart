import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../config/api_config.dart';
import '../models/product.dart';
import '../core/database/database_helper.dart';
import '../core/services/connectivity_service.dart';
import 'api_service.dart';
import 'storage_service.dart';

class FavoriteService extends ChangeNotifier {
  final ApiService _api;
  final ConnectivityService _connectivity;
  final Set<String> _syncing = {};
  final Map<String, Future<void>> _tasks = {};
  List<Product> _favorites = [];
  bool _isLoading = false, _disposed = false;
  String? _errorMessage;
  FavoriteService(this._api, this._connectivity, StorageService storage) {
    DatabaseHelper.scopeChanges.addListener(_onScopeChanged);
    _connectivity.addListener(_onConnectionChanged);
    loadLocalFavorites();
  }
  List<Product> get favorites => List.unmodifiable(_favorites);
  int get count => _favorites.length;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool isFavorite(String id) => _favorites.any((p) => p.id == id);
  bool _current(String owner) => !_disposed && DatabaseHelper.scope == owner;
  void _onScopeChanged() {
    _favorites = [];
    _isLoading = false;
    _errorMessage = null;
    notifyListeners();
    loadLocalFavorites();
  }

  void _onConnectionChanged() {
    if (_connectivity.isOnline) fetchFavorites();
  }

  Future<T> _serial<T>(String owner, Future<T> Function() action) {
    final previous = _tasks[owner] ?? Future<void>.value();
    final next = previous.then((_) => action());
    final settled = next.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _tasks[owner] = settled;
    settled.then((_) {
      if (identical(_tasks[owner], settled)) _tasks.remove(owner);
    });
    return next;
  }

  Future<void> loadLocalFavorites() async {
    final owner = DatabaseHelper.scope;
    if (owner == null || _disposed) return;
    await _serial<void>(owner, () async {
      if (_current(owner)) await _loadLocalFavorites();
    });
  }

  Future<void> fetchFavorites() async {
    final owner = DatabaseHelper.scope;
    if (owner == null || _disposed) return;
    await _serial<void>(owner, () async {
      if (_current(owner)) await _fetchFavorites();
    });
  }

  Future<bool> toggleFavorite(Product product) async {
    final owner = DatabaseHelper.scope;
    if (owner == null || _disposed) return false;
    return _serial<bool>(
      owner,
      () async => _current(owner) ? await _toggleFavorite(product) : false,
    );
  }

  Future<void> _loadLocalFavorites() async {
    final owner = DatabaseHelper.scope;
    if (owner == null || _disposed) return;
    try {
      final rows = await DatabaseHelper.instance
          .forScope(owner)
          .getLocalFavorites(owner.split(':').last);
      if (!_current(owner)) return;
      _favorites = rows
          .map(
            (r) => Product.fromJson(
              Map<String, dynamic>.from(
                jsonDecode(r['product_json'] as String) as Map,
              ),
            ),
          )
          .toList();
      notifyListeners();
    } catch (e) {
      if (_current(owner)) {
        _errorMessage = 'No se pudo cargar el respaldo de favoritos';
        notifyListeners();
      }
    }
  }

  Future<void> _sync(String owner) async {
    if (!_current(owner) || !_connectivity.isOnline || _syncing.contains(owner)) {
      return;
    }
    _syncing.add(owner);
    final db = DatabaseHelper.instance.forScope(owner);
    try {
      for (final row in await db.pendingFavoriteChanges(
        owner.split(':').last,
      )) {
        if (!_current(owner)) return;
        final desired = row['desired'] == 1;
        final response = desired
            ? await _api.postAuth(
                '${ApiConfig.apiUrl}/favorites',
                {'product_id': row['product_id']},
                null,
                owner,
              )
            : await _api.deleteAuth(
                '${ApiConfig.apiUrl}/favorites/${row['product_id']}',
              );
        if (!_current(owner)) return;
        if (!response.success && !(response.statusCode == 404 && !desired)) {
          _errorMessage =
              'Cambio guardado localmente; sincronización pendiente. ${response.error ?? ''}';
          return;
        }
        await db.acknowledgeFavoriteChange(
          row['product_id'].toString(),
          row['revision'].toString(),
        );
      }
    } finally {
      _syncing.remove(owner);
    }
  }

  Future<void> _fetchFavorites() async {
    final owner = DatabaseHelper.scope;
    if (owner == null || _disposed) return;
    final db = DatabaseHelper.instance.forScope(owner);
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      if (_connectivity.isOnline) {
        await _sync(owner);
        if (!_current(owner)) return;
        final response = await _api.getAuth('${ApiConfig.apiUrl}/favorites');
        if (!_current(owner)) return;
        if (!response.success || response.data is! List) {
          throw Exception(response.error ?? 'Respuesta inválida');
        }
        final products = (response.data as List).map((r) {
          if (r is! Map || r['producto'] is! Map) {
            throw const FormatException(
              'Actualiza la API: falta el producto del favorito',
            );
          }
          return Map<String, dynamic>.from(r['producto'] as Map);
        }).toList();
        await db.replaceFavoriteSnapshot(owner.split(':').last, products);
      }
      await _loadLocalFavorites();
    } catch (e) {
      if (_current(owner)) {
        _errorMessage = 'No se pudo actualizar favoritos: $e';
        await _loadLocalFavorites();
      }
    } finally {
      if (_current(owner)) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<bool> _toggleFavorite(Product product) async {
    final owner = DatabaseHelper.scope;
    if (owner == null || _disposed) return false;
    final desired = !isFavorite(product.id);
    final db = DatabaseHelper.instance.forScope(owner);
    try {
      await db.queueFavoriteChange(
        owner.split(':').last,
        product.toJson(),
        desired,
        const Uuid().v4(),
      );
      if (!_current(owner)) return false;
      await _loadLocalFavorites();
      await _sync(owner);
      if (_current(owner)) notifyListeners();
      return desired;
    } catch (e) {
      if (_current(owner)) {
        _errorMessage = 'No se pudo guardar el cambio de favorito: $e';
        notifyListeners();
      }
      return isFavorite(product.id);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    DatabaseHelper.scopeChanges.removeListener(_onScopeChanged);
    _connectivity.removeListener(_onConnectionChanged);
    super.dispose();
  }
}
