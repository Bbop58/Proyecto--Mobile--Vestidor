import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/database/database_helper.dart';
import '../models/receipt_document.dart';
import '../services/theme_service.dart';
import 'receipt_actions.dart';

class LocalReceiptActions extends StatelessWidget {
  final Map<String, dynamic> operation;
  const LocalReceiptActions({super.key, required this.operation});
  @override
  Widget build(BuildContext context) {
    final op = operation;
    if (op['server_entity_id'] != null) {
      return ReceiptActions(
        reference: ReceiptRef(
          op['operation_type'] == 'RESERVA_OFFLINE' ? 'reservation' : 'sale',
          op['server_entity_id'].toString(),
        ),
      );
    }
    if ((op['local_status'] == 'CONFIRMADA' || op['status'] == 'CONFIRMADA') &&
        op['server_receipt'] != null) {
      return ReceiptActions(
        reference: ReceiptRef('sale', op['server_receipt'].toString()),
      );
    }
    final tenant = context.watch<ThemeService?>()?.selectedTenant;
    final owner = DatabaseHelper.scope?.split(':').first;
    try {
      return ReceiptActions(
        provisional: ReceiptDocument.local(
          op,
          company: tenant?.id == owner ? tenant!.nombre : 'Empresa $owner',
        ),
      );
    } catch (_) {
      return const Text(
        'El detalle local no permite generar este PDF. Revisa el comprobante central al sincronizar.',
      );
    }
  }
}
