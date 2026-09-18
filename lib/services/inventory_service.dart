import '../config/api_config.dart';
import 'api_service.dart';

class InventoryAvailability {
  final String sucursalId;
  final String sucursalNombre;
  final String? ciudad;
  final int stockDisponible;
  final int stockReservado;

  InventoryAvailability({
    required this.sucursalId,
    required this.sucursalNombre,
    this.ciudad,
    required this.stockDisponible,
    required this.stockReservado,
  });

  factory InventoryAvailability.fromJson(Map<String, dynamic> json) {
    return InventoryAvailability(
      sucursalId: json['sucursal_id']?.toString() ?? '',
      sucursalNombre: json['sucursal']?.toString() ?? json['sucursal_nombre']?.toString() ?? '',
      ciudad: json['ciudad']?.toString(),
      stockDisponible: (json['stock_disponible'] is num)
          ? (json['stock_disponible'] as num).toInt()
          : int.tryParse(json['stock_disponible']?.toString() ?? '0') ?? 0,
      stockReservado: (json['stock_reservado'] is num)
          ? (json['stock_reservado'] as num).toInt()
          : int.tryParse(json['stock_reservado']?.toString() ?? '0') ?? 0,
    );
  }
}

class InventoryService {
  final ApiService _api;

  InventoryService(this._api);

  /// Disponibilidad de una variante (talla+color de un producto) en todas las sucursales.
  /// Backend endpoint: GET /inventario/disponibilidad?producto_id=...&talla=...&color=...
  Future<List<InventoryAvailability>> getProductAvailability({
    required String productoId,
    String? talla,
    String? color,
  }) async {
    final params = <String, String>{'producto_id': productoId};
    if (talla != null && talla.isNotEmpty) params['talla'] = talla;
    if (color != null && color.isNotEmpty) params['color'] = color;

    final uri = Uri.parse('${ApiConfig.apiUrl}/inventario/disponibilidad')
        .replace(queryParameters: params);
    final response = await _api.getAuth(uri.toString());
    if (response.success && response.data is List) {
      // Group by sucursal — sum stock_disponible across variants matching filter
      final Map<String, InventoryAvailability> bySucursal = {};
      for (final item in (response.data as List)) {
        final avail = InventoryAvailability.fromJson(item as Map<String, dynamic>);
        final existing = bySucursal[avail.sucursalId];
        if (existing == null) {
          bySucursal[avail.sucursalId] = avail;
        } else {
          bySucursal[avail.sucursalId] = InventoryAvailability(
            sucursalId: existing.sucursalId,
            sucursalNombre: existing.sucursalNombre,
            ciudad: existing.ciudad,
            stockDisponible: existing.stockDisponible + avail.stockDisponible,
            stockReservado: existing.stockReservado + avail.stockReservado,
          );
        }
      }
      return bySucursal.values.toList()
        ..sort((a, b) => b.stockDisponible.compareTo(a.stockDisponible));
    }
    return [];
  }
}
