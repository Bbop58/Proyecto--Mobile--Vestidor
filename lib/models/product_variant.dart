class ProductVariant {
  final String id;
  final String productoId;
  final String talla;
  final String color;
  final String codigoSku;
  final double precioAdicional;
  final String? imagenUrl;
  final bool activo;

  ProductVariant({
    required this.id,
    required this.productoId,
    required this.talla,
    required this.color,
    required this.codigoSku,
    required this.precioAdicional,
    this.imagenUrl,
    required this.activo,
  });

  factory ProductVariant.fromJson(Map<String, dynamic> json) {
    final rawPrecio = json['precio_extra'] ?? json['precio_adicional'];
    double parsedPrecio = 0.0;
    if (rawPrecio is num) {
      parsedPrecio = rawPrecio.toDouble();
    } else if (rawPrecio != null) {
      parsedPrecio = double.tryParse(rawPrecio.toString()) ?? 0.0;
    }

    return ProductVariant(
      id: json['id']?.toString() ?? '',
      productoId: (json['producto_id'] ?? json['productoId'])?.toString() ?? '',
      talla: json['talla']?.toString() ?? '',
      color: json['color']?.toString() ?? '',
      codigoSku: (json['sku'] ?? json['codigo_sku'] ?? '')?.toString() ?? '',
      precioAdicional: parsedPrecio,
      imagenUrl: json['imagen_url']?.toString(),
      activo: json['activo'] ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'producto_id': productoId,
      'talla': talla,
      'color': color,
      'codigo_sku': codigoSku,
      'precio_adicional': precioAdicional,
      'imagen_url': imagenUrl,
      'activo': activo,
    };
  }
}
