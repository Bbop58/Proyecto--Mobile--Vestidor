import '../config/api_config.dart';
import '../models/product.dart';
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

  /// Stock de una variante concreta en una sucursal; nunca suma tallas o colores.
  Future<List<Map<String, dynamic>>> getBranchVariantAvailability({
    required String sucursalId,
    required List<Product> products,
  }) async {
    final variants = <String, Map<String, dynamic>>{};
    for (final product in products.where((p) => p.activo)) {
      for (final variant in product.variantes.where((v) => v.activo)) {
        if (variant.codigoSku.isEmpty || variant.id.isEmpty ||
            variants.containsKey(variant.codigoSku)) {
          throw const FormatException('El catálogo no identifica cada variante por SKU');
        }
        variants[variant.codigoSku] = {'variante_id': variant.id,
          'producto_id': product.id, 'sku': variant.codigoSku,
          'nombre': product.nombre, 'talla': variant.talla, 'color': variant.color};
      }
    }
    if (variants.isEmpty) throw const FormatException('No hay variantes para preparar caja');
    final uri = Uri.parse('${ApiConfig.apiUrl}/inventario/disponibilidad')
        .replace(queryParameters: {'sucursal_id': sucursalId});
    final response = await _api.getAuth(uri.toString());
    if (!response.success) throw StateError(response.error ?? 'No se pudo consultar inventario');
    if (response.data is! List) throw const FormatException('Inventario incompleto');
    final found = <String>{};
    final result = <Map<String, dynamic>>[];
    for (final raw in response.data as List) {
      if (raw is! Map) throw const FormatException('Inventario inválido');
      final row = Map<String, dynamic>.from(raw);
      final sku = row['sku'];
      final variant = variants[sku];
      if (variant == null) continue; // Other tenant or stale catalogue row never enters the snapshot.
      if (row['sucursal_id']?.toString() != sucursalId ||
          row['producto_id']?.toString() != variant['producto_id'] ||
          row['talla']?.toString() != variant['talla'] ||
          row['color']?.toString() != variant['color'] ||
          row['stock_disponible'] is! int || row['stock_disponible'] <= 0 ||
          row['precio'] is! num || !(row['precio'] as num).toDouble().isFinite ||
          (row['precio'] as num) < 0 || !found.add(sku.toString())) {
        throw const FormatException('Inventario incoherente con el catálogo');
      }
      result.add({...variant, 'sucursal_id': sucursalId,
        'stock_disponible': row['stock_disponible'], 'precio': row['precio']});
    }
    if (result.isEmpty) throw const FormatException('No hay stock comprobado para la caja');
    return result;
  }

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
    if(!response.success) { throw Exception(response.error ?? 'No se pudo cargar la información. Intenta nuevamente.'); }
    throw const FormatException('La respuesta no contiene una lista válida');
  }
}
