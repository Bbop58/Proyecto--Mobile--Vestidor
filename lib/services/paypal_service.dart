import 'api_service.dart';
import '../config/api_config.dart';

class PayPalService {
  final ApiService _api;
  String? _errorMessage;

  String? get errorMessage => _errorMessage;

  PayPalService(this._api);

  /// Obtener configuración de PayPal Sandbox desde el backend
  Future<Map<String, dynamic>?> getConfig() async {
    _errorMessage = null;
    final res = await _api.getAuth(ApiConfig.paypalConfigUrl);
    if (res.success && res.data != null) {
      return res.data as Map<String, dynamic>;
    }
    _errorMessage = res.error;
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
    _errorMessage = null;
    final payload = {
      'monto_bob': montoBob,
      if (sucursalId != null) 'sucursal_id': sucursalId,
      if (reservaId != null) 'reserva_id': reservaId,
      'descripcion': descripcion ?? 'Compra en FICCT STORE',
      if (items != null) 'items': items,
      'return_url': '${ApiConfig.apiUrl}/payments/paypal/return',
      'cancel_url': '${ApiConfig.apiUrl}/payments/paypal/cancel',
    };

    final res = await _api.postAuth(
      ApiConfig.paypalCreateOrderUrl,
      payload,
      const Duration(seconds: 35),
    );
    if (res.success && res.data != null) {
      return res.data as Map<String, dynamic>;
    }
    _errorMessage = res.error;
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
    _errorMessage = null;
    final payload = {
      'order_id': orderId,
      'sucursal_id': sucursalId,
      'detalles': detalles,
      if (clienteId != null) 'cliente_id': clienteId,
      if (reservaId != null) 'reserva_id': reservaId,
      if (nota != null) 'nota': nota,
    };

    final res = await _api.postAuth(
      ApiConfig.paypalCaptureOrderUrl,
      payload,
      const Duration(seconds: 45),
    );
    if (res.success && res.data != null) {
      return res.data as Map<String, dynamic>;
    }
    _errorMessage = res.error;
    return null;
  }
}
