import '../config/api_config.dart';
import 'api_service.dart';

class Season {
  final String id;
  final String nombre;
  final bool activa;

  Season({required this.id, required this.nombre, required this.activa});

  factory Season.fromJson(Map<String, dynamic> json) {
    return Season(
      id: json['id']?.toString() ?? '',
      nombre: json['nombre']?.toString() ?? '',
      activa: json['activa'] == true || json['activo'] == true,
    );
  }
}

class SeasonService {
  final ApiService _api;

  SeasonService(this._api);

  Future<List<Season>> getSeasons() async {
    final response = await _api.getAuth('${ApiConfig.apiUrl}/temporadas');
    if (response.success && response.data is List) {
      return (response.data as List)
          .map((json) => Season.fromJson(json as Map<String, dynamic>))
          .where((s) => s.activa)
          .toList();
    }
    return [];
  }
}
