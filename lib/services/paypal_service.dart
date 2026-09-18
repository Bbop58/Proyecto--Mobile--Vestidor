import 'api_service.dart';
import '../config/api_config.dart';

class PayPalService {
  final ApiService _api;

  PayPalService(this._api);

  /// Obtener configuración de PayPal Sandbox desde el backend
  Future<Map<String, dynamic>?> getConfig() async {
    final res = await _api.getAuth(ApiConfig.paypalConfigUrl);
    if (res.success && res.data != null) {
      return res.data as Map<String, dynamic>;
    }
    return null;
  }

  /// Crear una orden de pago en PayPal a través del backend
  Future<Map<String, dynamic>?> createOrder({
    required double montoBob,
    String? sucursalId,
    String? reservaId,
    String? descripcion,
    List<Map<String, dynamic>>? items,
  }) async {
    final payload = {
      'monto_bob': montoBob,
      if (sucursalId != null) 'sucursal_id': sucursalId,
      if (reservaId != null) 'reserva_id': reservaId,
      'descripcion': descripcion ?? 'Compra en FICCT STORE',
      if (items != null) 'items': items,
    };

    final res = await _api.postAuth(ApiConfig.paypalCreateOrderUrl, payload);
    if (res.success && res.data != null) {
      return res.data as Map<String, dynamic>;
    }
    return null;
  }

  /// Capturar una orden de PayPal aprobada y registrar la venta oficial
  Future<Map<String, dynamic>?> captureOrder({
    required String orderId,
    required String sucursalId,
    required List<Map<String, dynamic>> detalles,
    String? clienteId,
    String? reservaId,
    String? nota,
  }) async {
    final payload = {
      'order_id': orderId,
      'sucursal_id': sucursalId,
      'detalles': detalles,
      if (clienteId != null) 'cliente_id': clienteId,
      if (reservaId != null) 'reserva_id': reservaId,
      if (nota != null) 'nota': nota,
    };

    final res = await _api.postAuth(ApiConfig.paypalCaptureOrderUrl, payload);
    if (res.success && res.data != null) {
      return res.data as Map<String, dynamic>;
    }
    return null;
  }
}
