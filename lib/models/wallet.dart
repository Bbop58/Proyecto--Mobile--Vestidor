class UserWallet {
  final String id;
  final String userId;
  final double saldoActual;
  final double saldoRetenido;
  final int nonceSecuencia;
  final String firmaBalance;
  final String moneda;
  final DateTime? ultimoSyncAt;

  UserWallet({
    required this.id,
    required this.userId,
    required this.saldoActual,
    this.saldoRetenido = 0.0,
    required this.nonceSecuencia,
    required this.firmaBalance,
    this.moneda = 'BOB',
    this.ultimoSyncAt,
  });

  factory UserWallet.fromJson(Map<String, dynamic> json) {
    return UserWallet(
      id: json['id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      saldoActual: (json['saldo_actual'] as num?)?.toDouble() ?? 0.0,
      saldoRetenido: (json['saldo_retenido'] as num?)?.toDouble() ?? 0.0,
      nonceSecuencia: (json['nonce_secuencia'] as num?)?.toInt() ?? 0,
      firmaBalance: json['firma_balance']?.toString() ?? '',
      moneda: json['moneda']?.toString() ?? 'BOB',
      ultimoSyncAt: json['ultimo_sync_at'] != null
          ? DateTime.tryParse(json['ultimo_sync_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'saldo_actual': saldoActual,
      'saldo_retenido': saldoRetenido,
      'nonce_secuencia': nonceSecuencia,
      'firma_balance': firmaBalance,
      'moneda': moneda,
      'ultimo_sync_at': ultimoSyncAt?.toIso8601String(),
    };
  }
}

class WalletTxItem {
  final String id;
  final String tipo;
  final double monto;
  final double saldoAnterior;
  final double saldoPosterior;
  final String descripcion;
  final DateTime fecha;

  WalletTxItem({
    required this.id,
    required this.tipo,
    required this.monto,
    required this.saldoAnterior,
    required this.saldoPosterior,
    required this.descripcion,
    required this.fecha,
  });

  factory WalletTxItem.fromJson(Map<String, dynamic> json) {
    return WalletTxItem(
      id: json['id']?.toString() ?? '',
      tipo: json['tipo']?.toString() ?? 'DESCONOCIDO',
      monto: (json['monto'] as num?)?.toDouble() ?? 0.0,
      saldoAnterior: (json['saldo_anterior'] as num?)?.toDouble() ?? 0.0,
      saldoPosterior: (json['saldo_posterior'] as num?)?.toDouble() ?? 0.0,
      descripcion: json['descripcion']?.toString() ?? '',
      fecha: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : (json['fecha'] != null ? DateTime.tryParse(json['fecha'].toString()) ?? DateTime.now() : DateTime.now()),
    );
  }
}

