import '../config/api_config.dart';
import '../models/voice_report.dart';
import 'api_service.dart';

class VoiceReportService {
  final ApiService api;
  VoiceReportService(this.api);

  Future<VoiceReport> query(String question) async {
    final text = question.trim();
    if (text.length < 3 || text.length > 500) {
      throw const FormatException(
        'Escribe una pregunta de 3 a 500 caracteres.',
      );
    }
    final response = await api.postAuth(ApiConfig.voiceReportQueryUrl, {
      'pregunta': text,
      'limite': 100,
    }, const Duration(seconds: 45));
    if (!response.success) {
      throw FormatException(response.error ?? 'No se pudo generar el reporte.');
    }
    if (response.data is! Map) {
      throw const FormatException('El reporte recibido no es válido.');
    }
    return VoiceReport.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }
}
