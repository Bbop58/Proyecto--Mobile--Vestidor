import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../config/api_config.dart';
import '../models/product.dart';
import '../core/database/database_helper.dart';
import '../core/services/connectivity_service.dart';
import 'api_service.dart';
import 'storage_service.dart';

class FavoriteService extends ChangeNotifier {
  final ApiService _api;
  final ConnectivityService _connectivity;
  final StorageService _storage;
  final DatabaseHelper _db = DatabaseHelper.instance;

  List<Product> _favorites = [];
  final Set<String> _favoriteIds = {};
  bool _isLoading = false;
  String? _errorMessage;

  FavoriteService(this._api, this._connectivity, this._storage) {
    // Carga inicial local
    loadLocalFavorites();
  }

  List<Product> get favorites => List.unmodifiable(_favorites);
  int get count => _favorites.length;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  bool isFavorite(String productId) => _favoriteIds.contains(productId);

  /// Carga inicial rápida desde SQLite
  Future<void> loadLocalFavorites() async {
    try {
      final userId = await _storage.getUserId();
      final local = await _db.getLocalFavorites(userId);
      _favorites = local.map((row) {
        final json = jsonDecode(row['product_json'] as String) as Map<String, dynamic>;
        return Product.fromJson(json);
      }).toList();

      _favoriteIds.clear();
      _favoriteIds.addAll(_favorites.map((p) => p.id));
      notifyListeners();
    } catch (e) {
      debugPrint('[FAVORITE SERVICE] Error cargando favoritos locales: $e');
    }
  }

  /// Consulta la lista de favoritos desde el servidor y sincroniza con SQLite
  Future<void> fetchFavorites() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final userId = await _storage.getUserId();

    if (_connectivity.isOnline) {
      try {
        final res = await _api.getAuth('${ApiConfig.apiUrl}/favorites');
        if (res.success && res.data is List) {
          final list = res.data as List;
          final List<Product> fetched = [];

          for (final item in list) {
            final m = item as Map<String, dynamic>;
            final prodMap = m['producto'] as Map<String, dynamic>?;
            if (prodMap != null) {
              final prod = Product.fromJson(prodMap);
              fetched.add(prod);
              // Guardar copia local en SQLite
              await _db.saveLocalFavorite(prod.id, userId, jsonEncode(prod.toJson()));
            }
          }

          _favorites = fetched;
          _favoriteIds.clear();
          _favoriteIds.addAll(fetched.map((p) => p.id));
          _isLoading = false;
          notifyListeners();
          return;
        }
      } catch (e) {
        debugPrint('[FAVORITE SERVICE] Error remoto: $e');
      }
    }

    // Fallback: cargar de SQLite
    await loadLocalFavorites();
    _isLoading = false;
    notifyListeners();
  }

  /// Alterna el estado de favorito (Agregar o Quitar)
  Future<bool> toggleFavorite(Product product) async {
    final userId = await _storage.getUserId();
    final bool currentlyFav = _favoriteIds.contains(product.id);

    if (currentlyFav) {
      // 1. Quitar de favoritos (Optimista)
      _favoriteIds.remove(product.id);
      _favorites.removeWhere((p) => p.id == product.id);
      notifyListeners();

      await _db.removeLocalFavorite(product.id);

      if (_connectivity.isOnline) {
        try {
          await _api.deleteAuth('${ApiConfig.apiUrl}/favorites/${product.id}');
        } catch (e) {
          debugPrint('[FAVORITE SERVICE] Error eliminando remoto: $e');
        }
      }
      return false;
    } else {
      // 2. Agregar a favoritos (Optimista)
      _favoriteIds.add(product.id);
      _favorites.insert(0, product);
      notifyListeners();

      await _db.saveLocalFavorite(product.id, userId, jsonEncode(product.toJson()));

      if (_connectivity.isOnline) {
        try {
          await _api.postAuth(
            '${ApiConfig.apiUrl}/favorites',
            {'product_id': product.id},
          );
        } catch (e) {
          debugPrint('[FAVORITE SERVICE] Error agregando remoto: $e');
        }
      }
      return true;
    }
  }
}

