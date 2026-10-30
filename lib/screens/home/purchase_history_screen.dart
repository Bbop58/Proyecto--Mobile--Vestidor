import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../services/sale_service.dart';

class PurchaseHistoryScreen extends StatefulWidget {
  const PurchaseHistoryScreen({super.key});

  @override
  State<PurchaseHistoryScreen> createState() => _PurchaseHistoryScreenState();
}

class _PurchaseHistoryScreenState extends State<PurchaseHistoryScreen> {
  List<Sale> _sales = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadSales();
  }

  Future<void> _loadSales() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final service = context.read<SaleService>();
      final list = await service.getMySales();
      if (mounted) {
        setState(() {
          _sales = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error al cargar historial: ${e.toString()}';
          _isLoading = false;
        });
      }
    }
  }

  String _formatDate(String rawDate) {
    try {
      final dt = DateTime.parse(rawDate).toLocal();
      final months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
      return '${dt.day} ${months[dt.month - 1]}. ${dt.year}';
    } catch (_) {
      return rawDate;
    }
  }

  Color _estadoColor(String estado) {
    switch (estado.toUpperCase()) {
      case 'COMPLETADA':
        return AppTheme.successColor;
      case 'CANCELADA':
        return AppTheme.errorColor;
      case 'PENDIENTE':
        return AppTheme.warningColor;
      default:
        return AppTheme.accentColor;
    }
  }

  IconData _paymentIcon(String metodo) {
    switch (metodo.toUpperCase()) {
      case 'TARJETA':
        return Icons.credit_card_rounded;
      case 'QR':
        return Icons.qr_code_rounded;
      default:
        return Icons.payments_rounded;
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
          'Historial de Compras',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: textPrimary),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: textSecondary),
            onPressed: _loadSales,
            tooltip: 'Actualizar',
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: accent))
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 48, color: AppTheme.errorColor),
                        const SizedBox(height: 12),
                        Text(_errorMessage!,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: textSecondary)),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _loadSales,
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
              : _sales.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.receipt_long_outlined,
                              size: 64, color: textSecondary.withValues(alpha: 0.4)),
                          const SizedBox(height: 16),
                          Text(
                            'Sin compras registradas',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: textPrimary),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Aquí verás el historial de tus compras digitales',
                            style: TextStyle(fontSize: 13, color: textSecondary),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      color: accent,
                      onRefresh: _loadSales,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _sales.length,
                        separatorBuilder: (ctx, index) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final sale = _sales[index];
                          final estadoColor = _estadoColor(sale.estado);
                          return InkWell(
                            onTap: () => _showOfficialReceipt(sale),
                            borderRadius: BorderRadius.circular(AppTheme.borderRadiusLarge),
                            child: Container(
                            decoration: BoxDecoration(
                              color: cardBg,
                              borderRadius:
                                  BorderRadius.circular(AppTheme.borderRadiusLarge),
                              border: Border.all(color: border),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.03),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: accent.withValues(alpha: 0.1),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(_paymentIcon(sale.metodoPago),
                                            color: accent, size: 20),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              sale.codigoVenta ?? 'Compra Digital',
                                              style: TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w700,
                                                  color: textPrimary),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              _formatDate(sale.fechaCreacion),
                                              style: TextStyle(
                                                  fontSize: 12, color: textSecondary),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            'Bs. ${sale.total.toStringAsFixed(2)}',
                                            style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w800,
                                                color: accent),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: estadoColor.withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(4),
                                              border: Border.all(
                                                  color:
                                                      estadoColor.withValues(alpha: 0.3)),
                                            ),
                                            child: Text(
                                              sale.estado,
                                              style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w700,
                                                  color: estadoColor),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                if (sale.detalles.isNotEmpty) ...[
                                  Divider(color: border, height: 1),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 10),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${sale.detalles.length} ${sale.detalles.length == 1 ? "prenda" : "prendas"}',
                                          style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: textSecondary),
                                        ),
                                        const SizedBox(height: 6),
                                        ...sale.detalles.take(3).map((d) => Padding(
                                              padding:
                                                  const EdgeInsets.only(bottom: 3),
                                              child: Row(
                                                children: [
                                                  Icon(Icons.fiber_manual_record,
                                                      size: 6, color: textSecondary),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Text(
                                                      '${d.productoNombre ?? "Prenda"} ${d.talla != null ? "· ${d.talla}" : ""} ${d.color != null ? "· ${d.color}" : ""} × ${d.cantidad}',
                                                      style: TextStyle(
                                                          fontSize: 12,
                                                          color: textSecondary),
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            )),
                                        if (sale.detalles.length > 3)
                                          Text(
                                            '+ ${sale.detalles.length - 3} más...',
                                            style: TextStyle(
                                                fontSize: 11, color: accent),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                                if (sale.sucursalNombre != null) ...[
                                  Divider(color: border, height: 1),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 8),
                                    child: Row(
                                      children: [
                                        Icon(Icons.store_rounded,
                                            size: 14, color: textSecondary),
                                        const SizedBox(width: 6),
                                        Text(
                                          sale.sucursalNombre!,
                                          style: TextStyle(
                                              fontSize: 12, color: textSecondary),
                                        ),
                                        const Spacer(),
                                        Icon(Icons.payment_rounded,
                                            size: 14, color: textSecondary),
                                        const SizedBox(width: 4),
                                        Text(
                                          sale.metodoPago,
                                          style: TextStyle(
                                              fontSize: 12, color: textSecondary),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                        },
                      ),
                    ),
    );
  }

  void _showOfficialReceipt(Sale sale) {
    final textPrimary = AppTheme.getTextPrimary(context);
    final textSecondary = AppTheme.getTextSecondary(context);
    final cardBg = AppTheme.getCardBg(context);
    final accent = AppTheme.getAccent(context);
    final border = AppTheme.getBorder(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(ctx).size.height * 0.82,
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('FashionStore Retail', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: textPrimary)),
                    Text('NIT: 1028374029 · Razón Social FashionStore SRL', style: TextStyle(fontSize: 11, color: textSecondary)),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const Divider(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: accent.withValues(alpha: 0.2)),
              ),
              child: Column(
                children: [
                  Text('NOTA DE VENTA OFICIAL', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: accent, letterSpacing: 0.5)),
                  const SizedBox(height: 4),
                  Text(sale.codigoVenta ?? 'VTA-OFICIAL', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: textPrimary)),
                  const SizedBox(height: 4),
                  Text('${_formatDate(sale.fechaCreacion)} · ${sale.sucursalNombre ?? "Sucursal Principal"}', style: TextStyle(fontSize: 12, color: textSecondary)),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text('Detalle de Prendas', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: textPrimary)),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.separated(
                itemCount: sale.detalles.length,
                separatorBuilder: (sepCtx, sepIdx) => Divider(color: border.withValues(alpha: 0.5), height: 12),
                itemBuilder: (itemCtx, i) {
                  final d = sale.detalles[i];
                  return Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(color: border.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(6)),
                        child: Text('${d.cantidad}x', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: textPrimary)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(d.productoNombre ?? 'Prenda', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: textPrimary)),
                            Text('Talla: ${d.talla ?? "-"} · Color: ${d.color ?? "-"}', style: TextStyle(fontSize: 11, color: textSecondary)),
                          ],
                        ),
                      ),
                      Text('Bs. ${d.subtotal.toStringAsFixed(2)}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: textPrimary)),
                    ],
                  );
                },
              ),
            ),
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Método de Pago:', style: TextStyle(fontSize: 13, color: textSecondary)),
                Text(sale.metodoPago, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: textPrimary)),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('TOTAL PAGADO:', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: textPrimary)),
                Text('Bs. ${sale.total.toStringAsFixed(2)}', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: accent)),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: border.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.verified_user_rounded, size: 14, color: AppTheme.successColor),
                      const SizedBox(width: 6),
                      Text('Garantía Retail: 30 Días para Cambios', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: textPrimary)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text('Presenta este comprobante digital en cualquier sucursal con la prenda limpia y su etiqueta original.', style: TextStyle(fontSize: 10, color: textSecondary)),
                ],
              ),
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(ctx),
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Cerrar Comprobante'),
              style: ElevatedButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
