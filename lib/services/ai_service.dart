import '../config/api_config.dart';
import 'api_service.dart';

class AIService {
  final ApiService _api;

  AIService(this._api);

  /// Solicita al backend de Gemini la generación fotorrealista del vestidor virtual.
  /// Retorna la imagen resultante en data-uri/base64 o lanza una excepción con el error en español.
  Future<String> generateVirtualTryOn({
    required String productoId,
    required String imagenBase64,
  }) async {
    final body = {
      'producto_id': productoId,
      'imagen_cliente_base64': imagenBase64.startsWith('data:')
          ? imagenBase64
          : 'data:image/jpeg;base64,$imagenBase64',
    };

    final response = await _api.postAuth(
      '${ApiConfig.apiUrl}/ai/virtual-tryon',
      body,
      const Duration(seconds: 90),
    );

    if (response.success && response.data != null && response.data is Map<String, dynamic>) {
      final map = response.data as Map<String, dynamic>;
      final img = map['imagen_resultado_base64']?.toString();
      if (img != null && img.isNotEmpty) {
        return img;
      }
    }

    final errorMsg = response.error ??
        response.message ??
        'No se pudo generar la imagen del vestidor virtual en este momento. Por favor, intenta más tarde.';
    throw Exception(errorMsg);
  }
}
