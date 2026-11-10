import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../config/api_config.dart';
import '../core/database/database_helper.dart';
import '../models/voice_report.dart';
import 'api_service.dart';

class VoiceReportExportService {
  final ApiService api;
  VoiceReportExportService(this.api);

  Future<Uint8List> pdfBytes(VoiceReport report) async {
    final doc = pw.Document();
    final fontData = await rootBundle.load('assets/fonts/NotoSans-Regular.ttf');
    final font = pw.Font.ttf(fontData);
    final rows = report.rows
        .map(
          (row) =>
              report.columns.map((col) => row[col]?.toString() ?? '—').toList(),
        )
        .toList();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: pw.ThemeData.withFont(base: font, bold: font),
        build: (_) => [
          pw.Text(
            'FashionStore · Reporte',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.Text('Consulta: ${report.question}'),
          pw.Text('Emitido: ${DateTime.now().toLocal()}'),
          pw.SizedBox(height: 8),
          pw.Text(report.interpretation),
          pw.SizedBox(height: 12),
          if (report.columns.isNotEmpty)
            pw.TableHelper.fromTextArray(
              headers: report.columns,
              data: rows,
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              cellStyle: const pw.TextStyle(fontSize: 8),
            ),
        ],
      ),
    );
    return doc.save();
  }

  Future<Uint8List> excelBytes(VoiceReport report) async {
    final response = await api.postAuthBinary(ApiConfig.voiceReportExcelUrl, {
      'pregunta': report.question,
      'interpretacion': report.interpretation,
      'columnas': report.columns,
      'filas': report.rows,
    });
    if (!response.success) {
      throw FormatException(response.error ?? 'No se pudo descargar el Excel.');
    }
    final bytes = response.data;
    if (bytes is! Uint8List ||
        bytes.length < 4 ||
        bytes[0] != 0x50 ||
        bytes[1] != 0x4b) {
      throw const FormatException('El Excel recibido no es válido.');
    }
    return bytes;
  }

  Future<bool> emailEnabled() async {
    final response=await api.getAuth('${ApiConfig.apiUrl}/receipts/capabilities');
    if(!response.success)throw FormatException(response.error??'No se pudo consultar el servicio de correo.');
    return response.data?['email_enabled']==true;
  }

  Future<Map<String,dynamic>> emailReport(VoiceReport report,String recipient,String operationId) async {
    final owner=DatabaseHelper.scope;
    if(owner==null)throw StateError('Inicia sesión para enviar el reporte.');
    final response=await api.postAuth(ApiConfig.voiceReportEmailUrl,{
      'recipient':recipient,'operation_id':operationId,'pregunta':report.question,
      'interpretacion':report.interpretation,'columnas':report.columns,'filas':report.rows,
    },const Duration(seconds:60),owner);
    if(!response.success)throw FormatException(response.error??'No se confirmó el envío. Revisa tu correo antes de reintentar.');
    return Map<String,dynamic>.from(response.data as Map);
  }

  Future<void> share(Uint8List bytes, String extension, String mime) async {
    if (bytes.isEmpty) throw const FormatException('El archivo está vacío.');
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            bytes,
            mimeType: mime,
            name: 'FashionStore-reporte.$extension',
          ),
        ],
        fileNameOverrides: ['FashionStore-reporte.$extension'],
        subject: 'Reporte FashionStore',
      ),
    );
  }
}
