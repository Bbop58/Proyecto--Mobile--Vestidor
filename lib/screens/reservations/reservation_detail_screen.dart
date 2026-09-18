import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../models/reservation.dart';

class ReservationDetailScreen extends StatelessWidget {
  final Reservation reservation;

  const ReservationDetailScreen({super.key, required this.reservation});

  Color _statusColor(BuildContext context) {
    switch (reservation.estado.toUpperCase()) {
      case 'PENDIENTE':
        return AppTheme.warningColor;
      case 'PREPARADA':
        return AppTheme.successColor;
      case 'RECOGIDA':
        return AppTheme.getAccent(context);
      case 'CANCELADA':
        return AppTheme.errorColor;
      case 'EXPIRADA':
        return AppTheme.getTextMuted(context);
      default:
        return AppTheme.getTextSecondary(context);
    }
  }

  String _statusLabel() {
    switch (reservation.estado.toUpperCase()) {
      case 'PENDIENTE':
        return 'Pendiente de preparación';
      case 'PREPARADA':
        return 'Lista para recoger';
      case 'RECOGIDA':
        return 'Entregada al cliente';
      case 'CANCELADA':
        return 'Cancelada';
      case 'EXPIRADA':
        return 'Expirada (24h)';
      default:
        return reservation.estado;
    }
  }

  IconData _statusIcon() {
    switch (reservation.estado.toUpperCase()) {
      case 'PENDIENTE':
        return Icons.hourglass_top_rounded;
      case 'PREPARADA':
        return Icons.check_box_rounded;
      case 'RECOGIDA':
        return Icons.shopping_bag_rounded;
      case 'CANCELADA':
        return Icons.cancel_rounded;
      case 'EXPIRADA':
        return Icons.timer_off_rounded;
      default:
        return Icons.info_outline_rounded;
    }
  }

  String _formatDate(String? rawDate) {
    if (rawDate == null || rawDate.isEmpty) return '—';
    try {
      final dt = DateTime.parse(rawDate).toLocal();
      final months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
      return '${dt.day} ${months[dt.month - 1]}. ${dt.year}  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return rawDate;
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
    final statusColor = _statusColor(context);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: cardBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        shape: Border(bottom: BorderSide(color: border)),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Detalle de Reserva',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: textPrimary),
            ),
            Text(
              reservation.numeroReserva.isNotEmpty ? reservation.numeroReserva : reservation.id.substring(0, 8).toUpperCase(),
              style: TextStyle(fontSize: 12, color: accent, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Estado Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppTheme.borderRadiusLarge),
                border: Border.all(color: statusColor.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(_statusIcon(), color: statusColor, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _statusLabel(),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: statusColor,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Creada el ${_formatDate(reservation.fechaCreacion)}',
                          style: TextStyle(fontSize: 12, color: textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Información de la reserva
            _buildInfoCard(
              context,
              title: 'Información de la Reserva',
              icon: Icons.info_outline_rounded,
              children: [
                _infoRow(context, Icons.store_rounded, 'Sucursal', reservation.sucursalNombre ?? '—'),
                if (reservation.sucursalCiudad != null)
                  _infoRow(context, Icons.location_city_rounded, 'Ciudad', reservation.sucursalCiudad!),
                _infoRow(context, Icons.calendar_today_rounded, 'Retiro esperado',
                    _formatDate(reservation.fechaHoraEsperada)),
                if (reservation.fechaExpiracion != null)
                  _infoRow(context, Icons.timer_outlined, 'Expira', _formatDate(reservation.fechaExpiracion)),
                if (reservation.fechaEntrega != null)
                  _infoRow(context, Icons.check_circle_outline, 'Entregada', _formatDate(reservation.fechaEntrega)),
                if (reservation.nota != null && reservation.nota!.isNotEmpty)
                  _infoRow(context, Icons.notes_rounded, 'Nota', reservation.nota!),
              ],
            ),
            const SizedBox(height: 16),

            // Prendas reservadas
            Container(
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(AppTheme.borderRadiusLarge),
                border: Border.all(color: border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                    child: Row(
                      children: [
                        Icon(Icons.checkroom_rounded, size: 18, color: accent),
                        const SizedBox(width: 8),
                        Text(
                          'Prendas Reservadas (${reservation.detalles.length})',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: textPrimary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  ...reservation.detalles.asMap().entries.map((entry) {
                    final i = entry.key;
                    final det = entry.value;
                    return Column(
                      children: [
                        if (i > 0) Divider(color: border, height: 1),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: accent.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
                                  border: Border.all(color: accent.withValues(alpha: 0.2)),
                                ),
                                child: Center(
                                  child: Icon(Icons.checkroom_rounded, color: accent, size: 22),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      det.productoNombre ?? 'Prenda',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        if (det.talla != null)
                                          _tagChip(context, 'Talla: ${det.talla}'),
                                        if (det.talla != null && det.color != null)
                                          const SizedBox(width: 6),
                                        if (det.color != null)
                                          _tagChip(context, det.color!),
                                        const SizedBox(width: 6),
                                        _tagChip(context, 'x${det.cantidad}'),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    'Bs. ${det.subtotal.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: accent,
                                    ),
                                  ),
                                  Text(
                                    'c/u: Bs. ${det.precioUnitario.toStringAsFixed(2)}',
                                    style: TextStyle(fontSize: 11, color: textSecondary),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  }),
                  Divider(color: border, height: 1),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Total estimado',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: textPrimary),
                        ),
                        Text(
                          'Bs. ${reservation.total.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(BuildContext context, {
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    final cardBg = AppTheme.getCardBg(context);
    final textPrimary = AppTheme.getTextPrimary(context);
    final accent = AppTheme.getAccent(context);
    final border = AppTheme.getBorder(context);

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(AppTheme.borderRadiusLarge),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Icon(icon, size: 18, color: accent),
                const SizedBox(width: 8),
                Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: textPrimary)),
              ],
            ),
          ),
          Divider(color: border, height: 1),
          ...children,
        ],
      ),
    );
  }

  Widget _infoRow(BuildContext context, IconData icon, String label, String value) {
    final textPrimary = AppTheme.getTextPrimary(context);
    final textSecondary = AppTheme.getTextSecondary(context);
    final border = AppTheme.getBorder(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Row(
            children: [
              Icon(icon, size: 16, color: textSecondary),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(fontSize: 13, color: textSecondary),
              ),
              const Spacer(),
              Flexible(
                child: Text(
                  value,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textPrimary),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        ),
        Divider(color: border, height: 1),
      ],
    );
  }

  Widget _tagChip(BuildContext context, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.getBorder(context).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.getBorder(context)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: AppTheme.getTextSecondary(context)),
      ),
    );
  }
}
