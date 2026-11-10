import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/config/api_config.dart';
import 'package:mobile/models/user.dart';
import 'package:mobile/services/api_service.dart';
import 'package:mobile/services/storage_service.dart';
import 'package:mobile/services/voice_report_export_service.dart';
import 'package:mobile/services/voice_report_service.dart';

class ReportApi extends ApiService {
  String? lastUrl;
  Map<String, dynamic>? lastBody;
  ReportApi() : super(StorageService());

  @override
  Future<ApiResponse> postAuth(
    String url, [
    Map<String, dynamic>? body,
    Duration? timeout,
    String? expectedScope,
  ]) async {
    lastUrl = url;
    lastBody = body;
    return ApiResponse(
      success: true,
      statusCode: 200,
      data: {
        'pregunta': body?['pregunta'],
        'interpretacion': 'Ingresos por sucursal',
        'resumen_hablado': 'Se vendieron Bs. 20',
        'columnas': ['sucursal', 'total'],
        'filas': [
          {'sucursal': 'Central', 'total': 20},
        ],
      },
    );
  }

  @override
  Future<ApiResponse> postAuthBinary(
    String url,
    Map<String, dynamic> body, {
    String? expectedScope,
  }) async {
    lastUrl = url;
    lastBody = body;
    return ApiResponse(
      success: true,
      statusCode: 200,
      data: Uint8List.fromList([0x50, 0x4b, 3, 4]),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('reports access requires both permission and active benefit', () {
    User user(List<String> perms, bool enabled) => User.fromJson({
      'id': '1',
      'email': 'admin@example.com',
      'full_name': 'Admin',
      'is_active': true,
      'created_at': '2026-11-09',
      'permissions': perms,
      'subscription_capabilities': {'reportes_ia': enabled},
    });
    expect(user(['ventas.reports'], true).canViewVoiceReports, isTrue);
    expect(user([], true).canViewVoiceReports, isFalse);
    expect(user(['ventas.reports'], false).canViewVoiceReports, isFalse);
  });

  test(
    'query and both exports keep question, interpretation and rows',
    () async {
      final api = ReportApi();
      final report = await VoiceReportService(api)
          .query(' Ventas por sucursal ');
      expect(api.lastUrl, ApiConfig.voiceReportQueryUrl);
      expect(api.lastBody, {'pregunta': 'Ventas por sucursal', 'limite': 100});
      expect(report.rows.single['total'], 20);
      final exports = VoiceReportExportService(api);
      final pdf = await exports.pdfBytes(report);
      expect(String.fromCharCodes(pdf.take(4)), '%PDF');
      final excel = await exports.excelBytes(report);
      expect(excel.take(2), [0x50, 0x4b]);
      expect(api.lastUrl, ApiConfig.voiceReportExcelUrl);
      expect(api.lastBody?['interpretacion'], report.interpretation);
      expect(api.lastBody?['filas'], report.rows);
    },
  );
}
