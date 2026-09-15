import '../config/api_config.dart';
import '../models/reservation.dart';
import 'api_service.dart';

class ReservationService {
  final ApiService _api;

  ReservationService(this._api);

  Future<List<Reservation>> getMyReservations() async {
    final response = await _api.getAuth('${ApiConfig.apiUrl}/reservas/mis-reservas');
    if (response.success && response.data is List) {
      return (response.data as List)
          .map((json) => Reservation.fromJson(json as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  Future<ApiResponse> createReservation({
    required String sucursalId,
    required List<Map<String, dynamic>> items,
    DateTime? fechaHoraEsperada,
    String? nota,
  }) async {
    // Por defecto, recogida esperada en 24 horas a partir de ahora
    final expectedPickup = fechaHoraEsperada ?? DateTime.now().add(const Duration(hours: 24));

    final body = {
      'sucursal_id': sucursalId,
      'fecha_hora_esperada': expectedPickup.toUtc().toIso8601String(),
      'items': items.map((i) => {
        'variante_id': i['variante_id'],
        'cantidad': i['cantidad'] is int ? i['cantidad'] : int.tryParse(i['cantidad'].toString()) ?? 1,
      }).toList(),
      if (nota != null && nota.isNotEmpty) 'nota': nota,
    };

    return await _api.postAuth('${ApiConfig.apiUrl}/reservas', body);
  }

  Future<ApiResponse> cancelReservation(String reservationId) async {
    return await _api.patchAuth('${ApiConfig.apiUrl}/reservas/$reservationId/cancelar');
  }
}
