import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../config/api_config.dart';
import '../core/database/database_helper.dart';
import '../models/receipt_document.dart';
import 'api_service.dart';

class ReceiptDocumentService {
  final ApiService api;
  ReceiptDocumentService(this.api);
  String path(ReceiptRef ref) =>
      '${ApiConfig.apiUrl}/receipts/${ref.kind}/${Uri.encodeComponent(ref.id)}';
  Future<ReceiptRef> resolve(ReceiptRef ref) async {
    if (ref.kind != 'sale' || !ref.id.startsWith('VTA-')) return ref;
    final result = await api.getAuth(
      '${ApiConfig.apiUrl}/receipts/sale-number/${Uri.encodeComponent(ref.id)}',
    );
    if (!result.success || result.data?['entity_id'] is! String) {
      throw StateError('No se pudo consultar el comprobante confirmado.');
    }
    return ReceiptRef('sale', result.data['entity_id']);
  }

  Future<Uint8List> pdf(ReceiptRef ref) async {
    final owner = DatabaseHelper.scope;
    final resolved = await resolve(ref);
    if (owner == null || owner != DatabaseHelper.scope){
      throw StateError('La sesión cambió.');
    }
    return api.getAuthPdf('${path(resolved)}/pdf', expectedScope: owner);
  }

  Future<String?> emailAddress(ReceiptRef ref) async {
    final result = await api.getAuth(path(await resolve(ref)));
    if (!result.success) {
      throw StateError('No se pudo consultar el comprobante');
    }
    return result.data?['customer']?['email']?.toString();
  }

  Future<bool> emailEnabled() async {
    final result = await api.getAuth(
      '${ApiConfig.apiUrl}/receipts/capabilities',
    );
    if (!result.success) {
      throw StateError('No se pudo consultar el servicio de correo');
    }
    return result.data?['email_enabled'] == true;
  }

  Future<Map<String, dynamic>> email(
    ReceiptRef ref,
    String recipient,
    String operationId,
  ) async {
    final owner = DatabaseHelper.scope;
    final resolved = await resolve(ref);
    if (owner == null || owner != DatabaseHelper.scope){
      throw StateError('La sesión cambió.');
    }
    final result = await api.postAuth(
      '${path(resolved)}/email',
      {'recipient': recipient, 'operation_id': operationId},
      const Duration(seconds: 60),
      owner,
    );
    if (!result.success) {
      throw StateError(
        'No se pudo confirmar el envío. Reintenta con el mismo destinatario para evitar duplicados.',
      );
    }
    return Map<String, dynamic>.from(result.data as Map);
  }

  Future<void> export(Uint8List bytes, String id) async {
    await Printing.layoutPdf(
      onLayout: (_) => bytes,
      name: 'comprobante-${id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')}.pdf',
    );
  }

  Future<Uint8List> provisional(ReceiptDocument note) async {
    final d = note.data;
    if (d['provisional'] != true) {
      throw StateError('Descarga el comprobante confirmado del servidor.');
    }
    final font = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
    );
    final pdf = pw.Document();
    pw.Widget line(String text) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 5),
      child: pw.Text(text),
    );
    final issued = DateTime.parse(d['issued_at'].toString())
        .toUtc()
        .subtract(const Duration(hours: 4));
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: pw.ThemeData.withFont(base: font, bold: font),
        footer: (context) => pw.Text(
          'PROVISIONAL · No es factura fiscal · ${context.pageNumber}/${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 8),
        ),
        build: (context) => [
          pw.Text(
            'COMPROBANTE PROVISIONAL',
            style: const pw.TextStyle(fontSize: 17),
          ),
          pw.SizedBox(height: 12),
          line(d['company']['name'].toString()),
          line(d['branch']['name'].toString()),
          line(d['title'].toString()),
          line('Operación local: ${d['entity_id']}'),
          line('Fecha (Bolivia UTC-4): ${issued.toIso8601String().replaceFirst('T',' ').replaceFirst('Z','')}'),
          line('Estado: ${d['status']}'),
          line(d['payment_status'].toString()),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            headers: [
              'Prenda / detalle',
              'Cantidad',
              'P. unitario Bs',
              'Importe Bs',
            ],
            data: (d['items'] as List)
                .map(
                  (i) => [
                    [i['description'], i['sku'], i['size'], i['color']]
                        .where((v) => v != null && v.toString().isNotEmpty)
                        .join(' · '),
                    '${i['quantity']}',
                    '${i['unit_price']}',
                    '${i['subtotal']}',
                  ],
                )
                .toList(),
            cellStyle: const pw.TextStyle(fontSize: 9),
            headerStyle: const pw.TextStyle(fontSize: 9),
          ),
          pw.SizedBox(height: 12),
          line('Total Bs ${d['total']}'),
          if (d['received'] != null)
            line(
              'Efectivo recibido Bs ${d['received']} · Cambio Bs ${d['change']}',
            ),
          ...((d['notes'] as List?) ?? []).map((n) => line(n.toString())),
        ],
      ),
    );
    return pdf.save();
  }
}
