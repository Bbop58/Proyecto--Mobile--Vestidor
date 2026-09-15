import '../config/api_config.dart';
import '../models/branch.dart';
import 'api_service.dart';

class BranchService {
  final ApiService _api;

  BranchService(this._api);

  Future<List<Branch>> getBranches({bool activaOnly = true}) async {
    final url = '${ApiConfig.apiUrl}/sucursales?activa_only=$activaOnly';
    final response = await _api.getAuth(url);
    if (response.success && response.data is List) {
      return (response.data as List)
          .map((json) => Branch.fromJson(json as Map<String, dynamic>))
          .where((b) => b.activa)
          .toList();
    }
    return [];
  }
}
