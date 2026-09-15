import '../config/api_config.dart';
import '../models/category.dart';
import 'api_service.dart';

class CategoryService {
  final ApiService _api;

  CategoryService(this._api);

  Future<List<Category>> getCategories() async {
    final response = await _api.getAuth('${ApiConfig.apiUrl}/categorias');
    if (response.success && response.data is List) {
      return (response.data as List)
          .map((json) => Category.fromJson(json as Map<String, dynamic>))
          .where((cat) => cat.activo)
          .toList();
    }
    return [];
  }
}
