import 'dart:convert';

class CashSnapshot {
  final String owner;
  final String branchId;
  final DateTime preparedAt;
  final DateTime validUntil;
  final List<Map<String, dynamic>> products;
  final List<Map<String, dynamic>> availability;

  CashSnapshot({required this.owner, required this.branchId, required this.preparedAt,
    required this.validUntil, required this.products, required this.availability});

  bool get isValid => DateTime.now().toUtc().isBefore(validUntil);

  Map<String, dynamic> toRow() => {
    'branch_id': branchId,
    'owner': owner,
    'prepared_at': preparedAt.toUtc().toIso8601String(),
    'valid_until': validUntil.toUtc().toIso8601String(),
    'payload_json': jsonEncode({'version': 1, 'products': products, 'availability': availability}),
  };

  factory CashSnapshot.fromRow(Map<String, dynamic> row) {
    final payload = jsonDecode(row['payload_json'] as String);
    if (payload is! Map || payload['version'] != 1 ||
        payload['products'] is! List || payload['availability'] is! List) {
      throw const FormatException('Instantánea de caja inválida');
    }
    return CashSnapshot(
      owner: row['owner'] as String,
      branchId: row['branch_id'] as String,
      preparedAt: DateTime.parse(row['prepared_at'] as String).toUtc(),
      validUntil: DateTime.parse(row['valid_until'] as String).toUtc(),
      products: (payload['products'] as List).map((v) => Map<String, dynamic>.from(v as Map)).toList(),
      availability: (payload['availability'] as List).map((v) => Map<String, dynamic>.from(v as Map)).toList(),
    );
  }
}
