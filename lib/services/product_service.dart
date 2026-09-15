import '../config/api_config.dart';
import '../models/product.dart';
import 'api_service.dart';

class ProductService {
  final ApiService _api;

  ProductService(this._api);

  Future<List<Product>> getProducts({
    String? categoriaId,
    String? temporada,
    String? search,
    bool? activo = true,
  }) async {
    final queryParams = <String, String>{};
    if (categoriaId != null && categoriaId.isNotEmpty) {
      queryParams['categoria_id'] = categoriaId;
    }
    if (temporada != null && temporada.isNotEmpty) {
      queryParams['temporada'] = temporada;
    }
    if (search != null && search.isNotEmpty) {
      queryParams['search'] = search;
    }
    if (activo != null) {
      queryParams['activo'] = activo.toString();
    }

    final uri = Uri.parse('${ApiConfig.apiUrl}/productos').replace(
      queryParameters: queryParams.isNotEmpty ? queryParams : null,
    );

    final response = await _api.getAuth(uri.toString());
    if (response.success && response.data is List) {
      return (response.data as List)
          .map((json) => Product.fromJson(json as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  Future<Product?> getProductById(String id) async {
    final response = await _api.getAuth('${ApiConfig.apiUrl}/productos/$id');
    if (response.success && response.data is Map<String, dynamic>) {
      return Product.fromJson(response.data as Map<String, dynamic>);
    }
    return null;
  }
}
