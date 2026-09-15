import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../models/reservation.dart';
import '../../services/reservation_service.dart';

class ReservationsScreen extends StatefulWidget {
  const ReservationsScreen({super.key});

  @override
  State<ReservationsScreen> createState() => _ReservationsScreenState();
}

class _ReservationsScreenState extends State<ReservationsScreen> {
  List<Reservation> _reservations = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadReservations();
  }

  Future<void> _loadReservations() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final service = context.read<ReservationService>();
      final list = await service.getMyReservations();
      if (mounted) {
        setState(() {
          _reservations = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error al cargar reservas: ${e.toString()}';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleCancel(Reservation res) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.getCardBg(ctx),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.borderRadiusLarge),
        ),
        title: Text(
          'Cancelar Reserva',
          style: TextStyle(
            color: AppTheme.getTextPrimary(ctx),
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        content: Text(
          '¿Estás seguro de que deseas cancelar la reserva ${res.numeroReserva}? El inventario apartado será liberado.',
          style: TextStyle(
            color: AppTheme.getTextSecondary(ctx),
            fontSize: 13,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Volver',
              style: TextStyle(color: AppTheme.getTextSecondary(ctx)),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.errorColor,
              foregroundColor: Colors.white,
            ),
            child: const Text('Sí, Cancelar'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final service = context.read<ReservationService>();
      final response = await service.cancelReservation(res.id);
      if (!mounted) return;
      if (response.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.successColor,
            content: Text('Reserva ${res.numeroReserva} cancelada exitosamente'),
          ),
        );
        _loadReservations();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.errorColor,
            content: Text(response.error ?? 'Error al cancelar reserva'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bg = AppTheme.getBg(context);
    final cardBg = AppTheme.getCardBg(context);
    final textPrimary = AppTheme.getTextPrimary(context);
    final textSecondary = AppTheme.getTextSecondary(context);
    final accent = AppTheme.getAccent(context);
    final border = AppTheme.getBorder(context);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: cardBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        shape: Border(bottom: BorderSide(color: border)),
        title: Text(
          'Mis Reservas Click & Collect',
          style: TextStyle(
            color: textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: RefreshIndicator(
        color: accent,
        onRefresh: _loadReservations,
        child: _isLoading
            ? Center(
                child: CircularProgressIndicator(color: accent),
              )
            : _errorMessage != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.error_outline, size: 48, color: AppTheme.errorColor),
                          const SizedBox(height: 12),
                          Text(
                            _errorMessage!,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: textSecondary),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: _loadReservations,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Reintentar'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: accent,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : _reservations.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.bookmark_border_rounded,
                                size: 64,
                                color: textSecondary.withValues(alpha: 0.5),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Aún no tienes reservas activas',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: textPrimary,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Explora la tienda y aparta tus prendas favoritas para recogerlas en tienda.',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 13, color: textSecondary),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _reservations.length,
                        itemBuilder: (context, index) {
                          final res = _reservations[index];
                          return _buildReservationCard(context, res);
                        },
                      ),
      ),
    );
  }

  Widget _buildReservationCard(BuildContext context, Reservation res) {
    final cardBg = AppTheme.getCardBg(context);
    final textPrimary = AppTheme.getTextPrimary(context);
    final textSecondary = AppTheme.getTextSecondary(context);
    final border = AppTheme.getBorder(context);
    final accent = AppTheme.getAccent(context);

    Color statusColor;
    Color statusBg;
    String statusLabel;

    switch (res.estado.toUpperCase()) {
      case 'PREPARADA':
        statusColor = const Color(0xFF2563EB);
        statusBg = const Color(0x1A2563EB);
        statusLabel = 'Lista para Entrega';
        break;
      case 'RECOGIDA':
      case 'COMPLETADA':
        statusColor = AppTheme.successColor;
        statusBg = AppTheme.successBg;
        statusLabel = 'Completada / Entregada';
        break;
      case 'CANCELADA':
        statusColor = AppTheme.errorColor;
        statusBg = AppTheme.errorBg;
        statusLabel = 'Cancelada';
        break;
      case 'EXPIRADA':
        statusColor = const Color(0xFF64748B);
        statusBg = const Color(0x1A64748B);
        statusLabel = 'Expirada';
        break;
      case 'PENDIENTE':
      default:
        statusColor = const Color(0xFFD97706);
        statusBg = const Color(0x1AD97706);
        statusLabel = 'Pendiente de Preparación';
        break;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header de la reserva
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: border.withValues(alpha: 0.05),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(AppTheme.borderRadiusMedium)),
              border: Border(bottom: BorderSide(color: border)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.confirmation_number_outlined, size: 18, color: accent),
                    const SizedBox(width: 8),
                    Text(
                      res.numeroReserva,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: textPrimary,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusBg,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Contenido de la reserva
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Sucursal
                Row(
                  children: [
                    Icon(Icons.location_on_outlined, size: 16, color: textSecondary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Retiro en: ${res.sucursalNombre ?? "Sucursal"}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Desglose de prendas
                Text(
                  'Prendas Reservadas:',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textSecondary),
                ),
                const SizedBox(height: 6),
                ...res.detalles.map((d) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            '• ${d.cantidad}x ${d.productoNombre ?? "Prenda"} (${d.talla ?? ""}/${d.color ?? ""})',
                            style: TextStyle(fontSize: 13, color: textPrimary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          'Bs. ${d.subtotal.toStringAsFixed(2)}',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: textSecondary),
                        ),
                      ],
                    ),
                  );
                }),

                Divider(height: 20, color: border),

                // Total y Botón de Acción
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Total a Pagar', style: TextStyle(fontSize: 11, color: textSecondary)),
                        Text(
                          'Bs. ${res.total.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: accent,
                          ),
                        ),
                      ],
                    ),
                    if (res.estado.toUpperCase() == 'PENDIENTE')
                      OutlinedButton.icon(
                        onPressed: () => _handleCancel(res),
                        icon: const Icon(Icons.close, size: 16, color: AppTheme.errorColor),
                        label: const Text(
                          'Cancelar',
                          style: TextStyle(color: AppTheme.errorColor, fontSize: 12),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppTheme.errorColor),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
