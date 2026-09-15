class ReservationDetail {
  final String id;
  final String varianteId;
  final String? productoNombre;
  final String? talla;
  final String? color;
  final String? codigoSku;
  final int cantidad;
  final double precioUnitario;
  final double subtotal;

  ReservationDetail({
    required this.id,
    required this.varianteId,
    this.productoNombre,
    this.talla,
    this.color,
    this.codigoSku,
    required this.cantidad,
    required this.precioUnitario,
    required this.subtotal,
  });

  factory ReservationDetail.fromJson(Map<String, dynamic> json) {
    return ReservationDetail(
      id: json['id']?.toString() ?? '',
      varianteId: json['variante_id']?.toString() ?? '',
      productoNombre: json['producto_nombre']?.toString(),
      talla: json['talla']?.toString(),
      color: json['color']?.toString(),
      codigoSku: json['variante_sku']?.toString() ?? json['codigo_sku']?.toString(),
      cantidad: (json['cantidad'] is num) ? (json['cantidad'] as num).toInt() : int.tryParse(json['cantidad']?.toString() ?? '1') ?? 1,
      precioUnitario: (json['precio_unitario'] is num)
          ? (json['precio_unitario'] as num).toDouble()
          : double.tryParse(json['precio_unitario']?.toString() ?? '0') ?? 0.0,
      subtotal: (json['subtotal'] is num)
          ? (json['subtotal'] as num).toDouble()
          : double.tryParse(json['subtotal']?.toString() ?? '0') ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'variante_id': varianteId,
      'producto_nombre': productoNombre,
      'talla': talla,
      'color': color,
      'variante_sku': codigoSku,
      'cantidad': cantidad,
      'precio_unitario': precioUnitario,
      'subtotal': subtotal,
    };
  }
}

class Reservation {
  final String id;
  final String numeroReserva; // Matches codigo or numero_reserva
  final String sucursalId;
  final String? sucursalNombre;
  final String? sucursalCiudad;
  final String clienteId;
  final String? clienteNombre;
  final String? clienteEmail;
  final String estado;
  final double total; // Matches total_estimado or total
  final String fechaCreacion;
  final String? fechaExpiracion;
  final String? fechaHoraEsperada;
  final String? fechaEntrega;
  final String? nota;
  final List<ReservationDetail> detalles;

  Reservation({
    required this.id,
    required this.numeroReserva,
    required this.sucursalId,
    this.sucursalNombre,
    this.sucursalCiudad,
    required this.clienteId,
    this.clienteNombre,
    this.clienteEmail,
    required this.estado,
    required this.total,
    required this.fechaCreacion,
    this.fechaExpiracion,
    this.fechaHoraEsperada,
    this.fechaEntrega,
    this.nota,
    this.detalles = const [],
  });

  factory Reservation.fromJson(Map<String, dynamic> json) {
    var rawDetalles = json['detalles'] as List<dynamic>? ?? [];
    List<ReservationDetail> parsedDetalles = rawDetalles
        .map((d) => ReservationDetail.fromJson(d as Map<String, dynamic>))
        .toList();

    return Reservation(
      id: json['id']?.toString() ?? '',
      numeroReserva: json['codigo']?.toString() ?? json['numero_reserva']?.toString() ?? '',
      sucursalId: json['sucursal_id']?.toString() ?? '',
      sucursalNombre: json['sucursal_nombre']?.toString(),
      sucursalCiudad: json['sucursal_ciudad']?.toString(),
      clienteId: json['cliente_id']?.toString() ?? '',
      clienteNombre: json['cliente_nombre']?.toString(),
      clienteEmail: json['cliente_email']?.toString(),
      estado: json['estado']?.toString() ?? 'PENDIENTE',
      total: (json['total_estimado'] is num)
          ? (json['total_estimado'] as num).toDouble()
          : (json['total'] is num)
              ? (json['total'] as num).toDouble()
              : double.tryParse(json['total_estimado']?.toString() ?? json['total']?.toString() ?? '0') ?? 0.0,
      fechaCreacion: json['created_at']?.toString() ?? json['fecha_creacion']?.toString() ?? '',
      fechaExpiracion: json['fecha_expiracion']?.toString(),
      fechaHoraEsperada: json['fecha_hora_esperada']?.toString(),
      fechaEntrega: json['fecha_recogida']?.toString() ?? json['fecha_entrega']?.toString(),
      nota: json['nota']?.toString(),
      detalles: parsedDetalles,
    );
  }
}
