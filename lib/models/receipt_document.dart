import 'dart:convert';

class ReceiptRef {
  final String kind, id;
  const ReceiptRef(this.kind, this.id);
}

/// Contract shared with the server. Local documents are always provisional.
class ReceiptDocument {
  final Map<String, dynamic> data;
  ReceiptDocument(this.data) {
    if (data['version'] != 1 ||
        data['currency'] != 'BOB' ||
        data['items'] is! List ||
        !RegExp(r'^-?\d+\.\d{2}$').hasMatch(data['total'].toString())) {
      throw const FormatException('Comprobante inválido');
    }
  }
  factory ReceiptDocument.local(
    Map<String, dynamic> op, {
    required String company,
  }) {
    String money(dynamic value) {
      final number = num.tryParse(value?.toString() ?? '');
      if (number == null || !number.isFinite) {
        throw const FormatException('Importe local inválido');
      }
      return number.toStringAsFixed(2);
    }

    final reservation = op['operation_type'] == 'RESERVA_OFFLINE';
    final wallet = op['operation_type'] == 'COMPRA_BILLETERA_OFFLINE';
    final raw = op['items_json'] is String
        ? jsonDecode(op['items_json'])
        : op['items'];
    if (raw is! List || raw.isEmpty) {
      throw const FormatException('No hay detalle local disponible');
    }
    return ReceiptDocument({
      'version': 1,
      'kind': reservation ? 'reservation' : 'sale',
      'entity_id': op['client_operation_id'],
      'title': reservation ? 'Nota de reserva' : 'Nota de venta',
      'number': op['client_operation_id'],
      'issued_at': op['fecha_local'] ?? op['created_at'],
      'company': {'name': company},
      'branch': {
        'name':
            op['sucursal_nombre'] ??
            op['sucursal_id'] ??
            'Sucursal no registrada',
      },
      'status': op['local_status'] ?? op['status'] ?? 'LOCAL_PENDIENTE',
      'payment_status': reservation
          ? 'NO ACREDITA PAGO'
          : wallet
          ? 'DÉBITO LOCAL PENDIENTE DE CONFIRMACIÓN'
          : 'EFECTIVO RECIBIDO LOCALMENTE; PENDIENTE DE CONFIRMACIÓN',
      'payment_method': reservation
          ? null
          : wallet
          ? 'BILLETERA'
          : 'EFECTIVO',
      'currency': 'BOB',
      'provisional': true,
      'items': raw
          .map(
            (i) => {
              'description':
                  i['producto_nombre'] ??
                  i['nombre'] ??
                  'Variante ${i['variante_id'] ?? i['id']}',
              'sku': i['sku'],
              'size': i['talla'],
              'color': i['color'],
              'quantity': i['cantidad'] ?? 1,
              'unit_price': money(i['precio_unitario'] ?? i['precio']),
              'subtotal': money(
                (num.parse((i['precio_unitario'] ?? i['precio']).toString())) *
                    (i['cantidad'] ?? 1),
              ),
            },
          )
          .toList(),
      'total': money(op['monto_total']),
      if (!reservation && !wallet) 'received': money(op['monto_recibido']),
      if (!reservation && !wallet) 'change': money(op['cambio']),
      'notes': [
        'Pendiente de confirmación central. No es factura fiscal.',
        if (op['notas'] != null) op['notas'],
      ],
    });
  }
}
