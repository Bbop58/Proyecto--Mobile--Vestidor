import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../services/wallet_service.dart';
import '../../core/services/connectivity_service.dart';
import '../../services/local_notification_service.dart';
import '../../utils/url_helper.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  final TextEditingController _amountController = TextEditingController(text: '100');
  bool _isProcessingTopup = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<WalletService>().fetchWallet();
    });
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _handlePayPalTopup() async {
    final amountText = _amountController.text.trim();
    final amount = double.tryParse(amountText);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor ingresa un monto válido en Bolivianos'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
      return;
    }

    final connectivity = context.read<ConnectivityService>();
    if (!connectivity.isOnline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Para recargar saldo mediante PayPal requieres conexión a Internet activa.'),
          backgroundColor: Colors.amber,
        ),
      );
      return;
    }

    setState(() => _isProcessingTopup = true);
    final walletService = context.read<WalletService>();

    try {
      final res = await walletService.initiatePayPalTopup(amount);
      setState(() => _isProcessingTopup = false);

      if (!mounted) return;
      if (res == null || res['approve_url'] == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(walletService.errorMessage ?? 'No se pudo iniciar la recarga con PayPal'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
        return;
      }

      final approveUrl = res['approve_url'].toString();
      final orderId = res['order_id']?.toString() ?? '';
      final montoUsd = (res['monto_usd'] as num?)?.toDouble() ?? (amount / 6.96);

      // Abrir navegador para autorizar cobro en PayPal Sandbox
      await UrlHelper.openUrl(approveUrl);

      // Mostrar modal para confirmar recarga completada
      if (!mounted) return;
      await showModalBottomSheet(
        context: context,
        isDismissible: false,
        backgroundColor: AppTheme.getCardBg(context),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) {
          bool confirming = false;
          return StatefulBuilder(
            builder: (bCtx, setModalState) {
              final textP = AppTheme.getTextPrimary(bCtx);
              final textS = AppTheme.getTextSecondary(bCtx);
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0070BA).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.account_balance_wallet_rounded, color: Color(0xFF0070BA), size: 28),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Ventana de Recarga PayPal Abierta',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textP),
                              ),
                              Text(
                                'Completa la autorización en PayPal Sandbox',
                                style: TextStyle(fontSize: 12, color: textS),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.getBg(bCtx),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.getBorder(bCtx)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Monto a Cargar:', style: TextStyle(color: textS, fontSize: 13)),
                          Text(
                            'Bs. ${amount.toStringAsFixed(2)} (~ \$${montoUsd.toStringAsFixed(2)} USD)',
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0070BA)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: confirming
                          ? null
                          : () async {
                              setModalState(() => confirming = true);
                              final ok = await context.read<WalletService>().confirmPayPalTopup(
                                orderId: orderId,
                                amountBob: amount,
                                amountUsd: montoUsd,
                              );
                              if (ok) {
                                await context.read<WalletService>().fetchHistory();
                                await LocalNotificationService.showNotification(
                                  title: 'Recarga Exitosa',
                                  body: 'Se han acreditado Bs. ${amount.toStringAsFixed(2)} en tu Billetera Virtual.',
                                );
                                if (ctx.mounted) Navigator.pop(ctx);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Billetera recargada con éxito (+Bs. ${amount.toStringAsFixed(2)})'),
                                      backgroundColor: AppTheme.successColor,
                                    ),
                                  );
                                }
                              } else {
                                setModalState(() => confirming = false);
                                final err = context.read<WalletService>().errorMessage ?? 'Error al acreditar fondos';
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(err),
                                      backgroundColor: AppTheme.errorColor,
                                    ),
                                  );
                                }
                              }
                            },
                      icon: confirming
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.check_circle_outline),
                      label: Text(confirming ? 'Acreditando Saldo...' : 'Confirmar y Acreditar Saldo'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.successColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () => UrlHelper.openUrl(approveUrl),
                      icon: const Icon(Icons.open_in_browser, size: 16),
                      label: const Text('Reabrir ventana de PayPal'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF0070BA),
                        side: const BorderSide(color: Color(0xFF0070BA)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text('Cancelar', style: TextStyle(color: textS)),
                    ),
                  ],
                ),
              );
            },
          );
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessingTopup = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.errorColor),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cardBg = AppTheme.getCardBg(context);
    final border = AppTheme.getBorder(context);
    final textP = AppTheme.getTextPrimary(context);
    final textS = AppTheme.getTextSecondary(context);
    final accent = AppTheme.getAccent(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final walletService = context.watch<WalletService>();
    final connectivity = context.watch<ConnectivityService>();
    final wallet = walletService.wallet;

    return Scaffold(
      backgroundColor: AppTheme.getBg(context),
      appBar: AppBar(
        title: const Text('Mi Billetera Virtual', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: cardBg,
        elevation: 0,
        iconTheme: IconThemeData(color: textP),
        actions: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: connectivity.isOnline ? Colors.green.withValues(alpha: 0.15) : Colors.amber.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: connectivity.isOnline ? Colors.green : Colors.amber),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  connectivity.isOnline ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
                  size: 14,
                  color: connectivity.isOnline ? Colors.green : Colors.amber,
                ),
                const SizedBox(width: 4),
                Text(
                  connectivity.isOnline ? 'Online' : 'Offline',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: connectivity.isOnline ? Colors.green : Colors.amber,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Actualizar saldo',
            onPressed: () => walletService.fetchWallet(),
          ),
        ],
      ),
      body: walletService.isLoading
          ? Center(child: CircularProgressIndicator(color: accent))
          : RefreshIndicator(
              onRefresh: () => walletService.fetchWallet(),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  // 1. Tarjeta de Saldo Virtual (Virtual Card)
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isDark
                            ? [const Color(0xFF1E3A8A), const Color(0xFF0F172A)]
                            : [const Color(0xFF0070BA), const Color(0xFF003087)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF0070BA).withValues(alpha: 0.35),
                          blurRadius: 16,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.account_balance_wallet_rounded, color: Colors.white, size: 24),
                                const SizedBox(width: 8),
                                const Text(
                                  'FICCT WALLET',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.2,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: const [
                                  Icon(Icons.offline_bolt_rounded, color: Colors.amberAccent, size: 14),
                                  SizedBox(width: 4),
                                  Text(
                                    'Prepago Offline',
                                    style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'Saldo Disponible para Compras',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Bs. ${(wallet?.saldoActual ?? 0.0).toStringAsFixed(2)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 34,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Divider(color: Colors.white.withValues(alpha: 0.2), height: 1),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Seguridad: HMAC-SHA256 • Nonce #${wallet?.nonceSecuencia ?? 0}',
                              style: const TextStyle(color: Colors.white60, fontSize: 11),
                            ),
                            const Icon(Icons.verified_user_rounded, color: Colors.greenAccent, size: 16),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // 2. Banner de Información Offline
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline_rounded, color: Colors.amber, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Tus fondos prepago están asegurados y sincronizados en tu dispositivo. Si se te corta el Internet, puedes pagar pedidos desde tu carrito usando este saldo.',
                            style: TextStyle(fontSize: 12, color: textP, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // 3. Módulo de Recarga de Saldo con PayPal
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.add_card_rounded, color: Color(0xFF0070BA), size: 22),
                            const SizedBox(width: 8),
                            Text(
                              'Recargar Saldo Online',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textP),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Carga dinero a tu billetera mediante PayPal para tener saldo disponible siempre:',
                          style: TextStyle(fontSize: 12, color: textS),
                        ),
                        const SizedBox(height: 14),

                        // Chips de montos rápidos
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [50.0, 100.0, 200.0, 500.0].map((amt) {
                            final isSelected = _amountController.text == amt.toStringAsFixed(0);
                            return ChoiceChip(
                              label: Text('Bs. ${amt.toStringAsFixed(0)}'),
                              selected: isSelected,
                              onSelected: (selected) {
                                if (selected) {
                                  setState(() => _amountController.text = amt.toStringAsFixed(0));
                                }
                              },
                              selectedColor: const Color(0xFF0070BA),
                              labelStyle: TextStyle(
                                color: isSelected ? Colors.white : textP,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 14),

                        // Input manual de monto
                        TextField(
                          controller: _amountController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            labelText: 'Monto a Recargar en Bolivianos (Bs.)',
                            prefixIcon: const Icon(Icons.attach_money_rounded),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          ),
                        ),
                        const SizedBox(height: 16),

                        ElevatedButton.icon(
                          onPressed: _isProcessingTopup ? null : _handlePayPalTopup,
                          icon: _isProcessingTopup
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : const Icon(Icons.payment_rounded),
                          label: Text(
                            _isProcessingTopup ? 'Iniciando PayPal...' : 'Recargar con PayPal Sandbox',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0070BA),
                            foregroundColor: Colors.white,
                            minimumSize: const Size(double.infinity, 48),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Center(
                          child: Text(
                            'Nota: También puedes recargar saldo en efectivo en la caja de cualquier sucursal.',
                            style: TextStyle(fontSize: 11, color: textS, fontStyle: FontStyle.italic),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // 4. Historial de Transacciones
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Historial de Movimientos',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textP),
                      ),
                      Text(
                        '${walletService.transactions.length} registros',
                        style: TextStyle(fontSize: 12, color: textS),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  if (walletService.transactions.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: border),
                      ),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(Icons.history_toggle_off_rounded, size: 36, color: textS),
                            const SizedBox(height: 8),
                            Text('Aún no tienes movimientos en tu billetera', style: TextStyle(color: textS, fontSize: 13)),
                          ],
                        ),
                      ),
                    )
                  else
                    ...walletService.transactions.map((tx) {
                      final isIngreso = tx.monto > 0;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: border),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: (isIngreso ? AppTheme.successColor : AppTheme.errorColor).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                isIngreso ? Icons.arrow_downward_rounded : Icons.shopping_bag_outlined,
                                color: isIngreso ? AppTheme.successColor : AppTheme.errorColor,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    tx.tipo.replaceAll('_', ' '),
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: textP),
                                  ),
                                  if (tx.descripcion.isNotEmpty)
                                    Text(
                                      tx.descripcion,
                                      style: TextStyle(fontSize: 11, color: textS),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  Text(
                                    '${tx.fecha.day}/${tx.fecha.month}/${tx.fecha.year} ${tx.fecha.hour.toString().padLeft(2, '0')}:${tx.fecha.minute.toString().padLeft(2, '0')}',
                                    style: TextStyle(fontSize: 10, color: textS),
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '${isIngreso ? "+" : ""}Bs. ${tx.monto.abs().toStringAsFixed(2)}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: isIngreso ? AppTheme.successColor : AppTheme.errorColor,
                                  ),
                                ),
                                Text(
                                  'Saldo: Bs. ${tx.saldoPosterior.toStringAsFixed(2)}',
                                  style: TextStyle(fontSize: 10, color: textS),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }),

                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }
}
