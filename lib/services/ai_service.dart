import 'dart:convert';
import '../config/api_config.dart';
import 'api_service.dart';

class MatchingProductItem {
  final String nombre;
  final String categoria;
  final String motivo;

  MatchingProductItem({
    required this.nombre,
    required this.categoria,
    required this.motivo,
  });

  factory MatchingProductItem.fromJson(Map<String, dynamic> json) {
    return MatchingProductItem(
      nombre: json['nombre']?.toString() ?? '',
      categoria: json['categoria']?.toString() ?? '',
      motivo: json['motivo']?.toString() ?? '',
    );
  }
}

class VirtualTryOnResult {
  final String imagenResultadoUrl;
  final String tallaSugerida;
  final String calceDetectado;
  final int nivelCoincidenciaPorcentaje;
  final String analisisSilueta;
  final String consejoEstilo;
  final List<MatchingProductItem> combinacionesSugeridas;

  VirtualTryOnResult({
    required this.imagenResultadoUrl,
    required this.tallaSugerida,
    required this.calceDetectado,
    required this.nivelCoincidenciaPorcentaje,
    required this.analisisSilueta,
    required this.consejoEstilo,
    required this.combinacionesSugeridas,
  });

  factory VirtualTryOnResult.fromJson(Map<String, dynamic> json) {
    final rawMatches = json['combinaciones_sugeridas'] as List<dynamic>? ?? [];
    return VirtualTryOnResult(
      imagenResultadoUrl: json['imagen_resultado_url']?.toString() ?? '',
      tallaSugerida: json['talla_sugerida']?.toString() ?? 'M',
      calceDetectado: json['calce_detectado']?.toString() ?? 'Regular Fit',
      nivelCoincidenciaPorcentaje: (json['nivel_coincidencia_porcentaje'] is num)
          ? (json['nivel_coincidencia_porcentaje'] as num).toInt()
          : 95,
      analisisSilueta: json['analisis_silueta']?.toString() ?? 'Análisis anatómico completado.',
      consejoEstilo: json['consejo_estilo']?.toString() ?? 'Excelente combinación.',
      combinacionesSugeridas: rawMatches
          .map((m) => MatchingProductItem.fromJson(m as Map<String, dynamic>))
          .toList(),
    );
  }
}

class AIService {
  final ApiService _api;

  AIService(this._api);

  /// Solicita el análisis y renderizado del Vestidor Virtual con IA
  Future<VirtualTryOnResult?> requestVirtualTryOn({
    required String varianteId,
    required String imagenBase64,
    int? alturaCm,
    int? pesoKg,
    String preferenciaCalce = 'REGULAR',
  }) async {
    final body = {
      'variante_id': varianteId,
      'imagen_cliente_base64': imagenBase64.startsWith('data:')
          ? imagenBase64
          : 'data:image/jpeg;base64,$imagenBase64',
      if (alturaCm != null) 'altura_cm': alturaCm,
      if (pesoKg != null) 'peso_kg': pesoKg,
      'preferencia_calce': preferenciaCalce,
    };

    final response = await _api.postAuth(
      '${ApiConfig.apiUrl}/ai/virtual-tryon',
      body,
    );

    if (response.success && response.data != null && response.data is Map<String, dynamic>) {
      return VirtualTryOnResult.fromJson(response.data as Map<String, dynamic>);
    }
    return null;
  }
}
