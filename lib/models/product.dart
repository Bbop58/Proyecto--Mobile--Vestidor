import 'product_variant.dart';
import '../config/api_config.dart';

class Product {
  final String id;
  final String codigo;
  final String nombre;
  final String? descripcion;
  final double precioBase;
  final double? precioOferta;
  final bool enOferta;
  final String? imagenUrl;
  final String? categoriaId;
  final String? categoriaNombre;
  final String? temporada;
  final String? proveedor;
  final bool activo;
  final List<ProductVariant> variantes;

  Product({
    required this.id,
    required this.codigo,
    required this.nombre,
    this.descripcion,
    required this.precioBase,
    this.precioOferta,
    this.enOferta = false,
    this.imagenUrl,
    this.categoriaId,
    this.categoriaNombre,
    this.temporada,
    this.proveedor,
    required this.activo,
    this.variantes = const [],
  });

  /// Retorna el precio activo considerando si el producto está en oferta
  double get precioEfectivo => (enOferta && precioOferta != null && precioOferta! > 0) ? precioOferta! : precioBase;

  /// Retorna el porcentaje de descuento si está en oferta
  int get porcentajeDescuento {
    if (!enOferta || precioOferta == null || precioOferta! <= 0 || precioBase <= 0) return 0;
    final pct = ((precioBase - precioOferta!) / precioBase) * 100;
    return pct > 0 ? pct.round() : 0;
  }

  factory Product.fromJson(Map<String, dynamic> json) {
    var rawVariantes = json['variantes'] as List<dynamic>? ?? [];
    List<ProductVariant> parsedVariantes = rawVariantes
        .map((v) => ProductVariant.fromJson(v as Map<String, dynamic>))
        .toList();

    final rawPrecio = json['precio_base'];
    double parsedPrecio = 0.0;
    if (rawPrecio is num) {
      parsedPrecio = rawPrecio.toDouble();
    } else if (rawPrecio != null) {
      parsedPrecio = double.tryParse(rawPrecio.toString()) ?? 0.0;
    }

    String? catNombre;
    if (json['categoria'] != null && json['categoria'] is Map) {
      catNombre = json['categoria']['nombre']?.toString();
    } else {
      catNombre = json['categoria_nombre']?.toString();
    }

    final id = json['id']?.toString() ?? '';
    final codigo = json['codigo']?.toString() ?? (id.length >= 8 ? id.substring(0, 8).toUpperCase() : id);

    final rawOferta = json['precio_oferta'];
    double? parsedOferta;
    if (rawOferta is num) {
      parsedOferta = rawOferta.toDouble();
    } else if (rawOferta != null) {
      parsedOferta = double.tryParse(rawOferta.toString());
    }
    final enOferta = json['en_oferta'] == true || json['en_oferta'] == 1;

    return Product(
      id: id,
      codigo: codigo,
      nombre: json['nombre']?.toString() ?? '',
      descripcion: json['descripcion']?.toString(),
      precioBase: parsedPrecio,
      precioOferta: parsedOferta,
      enOferta: enOferta,
      imagenUrl: (json['imagen_url'] != null && json['imagen_url'].toString().startsWith('/'))
          ? '${ApiConfig.baseUrl}${json['imagen_url']}'
          : json['imagen_url']?.toString(),
      categoriaId: json['categoria_id']?.toString(),
      categoriaNombre: catNombre,
      temporada: json['temporada']?.toString(),
      proveedor: json['proveedor']?.toString(),
      activo: json['activo'] ?? true,
      variantes: parsedVariantes,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'codigo': codigo,
      'nombre': nombre,
      'descripcion': descripcion,
      'precio_base': precioBase,
      'precio_oferta': precioOferta,
      'en_oferta': enOferta,
      'imagen_url': imagenUrl,
      'categoria_id': categoriaId,
      'categoria_nombre': categoriaNombre,
      'temporada': temporada,
      'proveedor': proveedor,
      'activo': activo,
      'variantes': variantes.map((v) => v.toJson()).toList(),
    };
  }
}
