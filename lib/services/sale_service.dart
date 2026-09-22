import '../config/api_config.dart';
import 'api_service.dart';

class SaleDetail {
  final String varianteId;
  final String? productoNombre;
  final String? talla;
  final String? color;
  final int cantidad;
  final double precioUnitario;
  final double subtotal;

  SaleDetail({
    required this.varianteId,
    this.productoNombre,
    this.talla,
    this.color,
    required this.cantidad,
    required this.precioUnitario,
    required this.subtotal,
  });

  factory SaleDetail.fromJson(Map<String, dynamic> json) {
    return SaleDetail(
      varianteId: json['variante_id']?.toString() ?? '',
      productoNombre: json['producto_nombre']?.toString(),
      talla: json['talla']?.toString(),
      color: json['color']?.toString(),
      cantidad: (json['cantidad'] is num) ? (json['cantidad'] as num).toInt() : 1,
      precioUnitario: (json['precio_unitario'] is num)
          ? (json['precio_unitario'] as num).toDouble()
          : double.tryParse(json['precio_unitario']?.toString() ?? '0') ?? 0.0,
      subtotal: (json['subtotal'] is num)
          ? (json['subtotal'] as num).toDouble()
          : double.tryParse(json['subtotal']?.toString() ?? '0') ?? 0.0,
    );
  }
}

class Sale {
  final String id;
  final String? codigoVenta;
  final String tipo; // PRESENCIAL | DIGITAL
  final String estado;
  final double total;
  final String metodoPago;
  final String? sucursalNombre;
  final String fechaCreacion;
  final List<SaleDetail> detalles;

  Sale({
    required this.id,
    this.codigoVenta,
    required this.tipo,
    required this.estado,
    required this.total,
    required this.metodoPago,
    this.sucursalNombre,
    required this.fechaCreacion,
    this.detalles = const [],
  });

  factory Sale.fromJson(Map<String, dynamic> json) {
    final rawDetalles = json['detalles'] as List<dynamic>? ?? [];
    return Sale(
      id: json['id']?.toString() ?? '',
      codigoVenta: json['numero_recibo']?.toString() ?? json['codigo_venta']?.toString(),
      tipo: json['tipo']?.toString() ?? 'DIGITAL',
      estado: json['estado']?.toString() ?? 'COMPLETADA',
      total: (json['monto_total'] is num)
          ? (json['monto_total'] as num).toDouble()
          : (json['total'] is num)
              ? (json['total'] as num).toDouble()
              : double.tryParse(json['monto_total']?.toString() ?? json['total']?.toString() ?? '0') ?? 0.0,
      metodoPago: json['metodo_pago']?.toString() ?? 'EFECTIVO',
      sucursalNombre: json['sucursal_nombre']?.toString(),
      fechaCreacion: json['created_at']?.toString() ?? json['fecha_venta']?.toString() ?? '',
      detalles: rawDetalles
          .map((d) => SaleDetail.fromJson(d as Map<String, dynamic>))
          .toList(),
    );
  }
}

class SaleService {
  final ApiService _api;

  SaleService(this._api);

  /// Obtener historial de compras del cliente autenticado
  Future<List<Sale>> getMySales() async {
    final response = await _api.getAuth('${ApiConfig.apiUrl}/ventas/mis-compras');
    if (response.success && response.data is List) {
      return (response.data as List)
          .map((json) => Sale.fromJson(json as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  /// Registrar una venta digital (compra directa desde la app)
  Future<ApiResponse> createDigitalSale({
    required String sucursalId,
    required List<Map<String, dynamic>> items,
    String? tokenPago,
    String? nota,
  }) async {
    final body = {
      'sucursal_id': sucursalId,
      if (tokenPago != null) 'token_pago': tokenPago,
      'items': items.map((i) => {
        'variante_id': i['variante_id'],
        'cantidad': i['cantidad'] is int ? i['cantidad'] : int.tryParse(i['cantidad'].toString()) ?? 1,
      }).toList(),
      if (nota != null && nota.isNotEmpty) 'nota': nota,
    };
    return await _api.postAuth('${ApiConfig.apiUrl}/ventas/digital', body);
  }
}
