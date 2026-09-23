import 'product_variant.dart';
import '../config/api_config.dart';

class Product {
  final String id;
  final String codigo;
  final String nombre;
  final String? descripcion;
  final double precioBase;
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
    this.imagenUrl,
    this.categoriaId,
    this.categoriaNombre,
    this.temporada,
    this.proveedor,
    required this.activo,
    this.variantes = const [],
  });

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

    return Product(
      id: id,
      codigo: codigo,
      nombre: json['nombre']?.toString() ?? '',
      descripcion: json['descripcion']?.toString(),
      precioBase: parsedPrecio,
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
