import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../models/branch.dart';
import '../../services/branch_service.dart';
import '../../services/cart_service.dart';
import '../../services/reservation_service.dart';
import '../../services/paypal_service.dart';
import '../../utils/url_helper.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  List<Branch> _branches = [];
  bool _isLoadingBranches = true;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadBranches();
  }

  Future<void> _loadBranches() async {
    try {
      final service = context.read<BranchService>();
      final branches = await service.getBranches();
      if (mounted) {
        setState(() {
          _branches = branches;
          _isLoadingBranches = false;
        });
        final cart = context.read<CartService>();
        if (cart.selectedBranch == null && branches.isNotEmpty) {
          cart.setSelectedBranch(branches.first);
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoadingBranches = false;
        });
      }
    }
  }

  Future<void> _handleConfirmReservation() async {
    final cart = context.read<CartService>();
    if (cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El carrito está vacío'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
      return;
    }

    if (cart.selectedBranch == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor selecciona una sucursal para recoger tu pedido'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final resService = context.read<ReservationService>();
      final items = cart.items
          .map((item) => {
                'variante_id': item.variant.id,
                'cantidad': item.quantity,
              })
          .toList();

      final response = await resService.createReservation(
        sucursalId: cart.selectedBranch!.id,
        items: items,
      );

      if (mounted) {
        setState(() => _isSubmitting = false);
        if (response.success) {
          final resData = response.data as Map<String, dynamic>?;
          final numeroReserva = resData?['codigo'] ?? resData?['numero_reserva'] ?? 'RES-CONFIRMADA';

          cart.clearCart();

          await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              backgroundColor: AppTheme.getCardBg(ctx),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.borderRadiusLarge),
              ),
              title: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: AppTheme.successColor, size: 28),
                  const SizedBox(width: 10),
                  Text(
                    '¡Reserva Creada!',
                    style: TextStyle(
                      color: AppTheme.getTextPrimary(ctx),
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tu pedido ha sido apartado exitosamente bajo el código:',
                    style: TextStyle(color: AppTheme.getTextSecondary(ctx), fontSize: 13),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                    decoration: BoxDecoration(
                      color: AppTheme.getAccent(ctx).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.getAccent(ctx).withValues(alpha: 0.3)),
                    ),
                    child: Center(
                      child: Text(
                        numeroReserva,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.getAccent(ctx),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Puedes pasar a retirarlo y pagarlo en mostrador en la sucursal seleccionada.',
                    style: TextStyle(color: AppTheme.getTextSecondary(ctx), fontSize: 12),
                  ),
                ],
              ),
              actions: [
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx); // Cierra dialog
                    Navigator.pop(context); // Cierra CartScreen
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.getAccent(ctx),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('Entendido'),
                ),
              ],
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.message ?? response.error ?? 'Error al procesar reserva'),
              backgroundColor: AppTheme.errorColor,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error inesperado: ${e.toString()}'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  Future<void> _handleDirectPurchase() async {
    final cart = context.read<CartService>();
    if (cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El carrito está vacío'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
      return;
    }

    if (cart.selectedBranch == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor selecciona una sucursal para despachar tu compra'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final paypalService = context.read<PayPalService>();
      final items = cart.items
          .map((item) => {
                'name': '${item.product.nombre} (${item.variant.talla}/${item.variant.color})',
                'quantity': item.quantity,
                'unit_amount_bob': item.unitPrice,
              })
          .toList();

      // 1. Crear la orden en PayPal Sandbox
      final orderRes = await paypalService.createOrder(
        montoBob: cart.total,
        sucursalId: cart.selectedBranch!.id,
        descripcion: 'Compra directa en App Móvil FICCT STORE',
        items: items,
      );

      if (!mounted) return;
      setState(() => _isSubmitting = false);

      if (orderRes == null || orderRes['order_id'] == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo iniciar la pasarela de PayPal. Verifica la conexión.'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
        return;
      }

      final orderId = orderRes['order_id'].toString();
      final approveUrl = orderRes['approve_url']?.toString() ?? 'https://www.sandbox.paypal.com/checkoutnow?token=$orderId';
      final montoUsd = (orderRes['monto_usd'] is num) ? (orderRes['monto_usd'] as num).toDouble() : (cart.total / 6.96);

      // 2. Abrir la ventana segura de PayPal Sandbox
      UrlHelper.openUrl(approveUrl);

      // 3. Mostrar diálogo de captura y confirmación
      if (!mounted) return;
      await showModalBottomSheet(
        context: context,
        isDismissible: false,
        enableDrag: false,
        backgroundColor: AppTheme.getCardBg(context),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) {
          bool isCapturing = false;
          return StatefulBuilder(
            builder: (bottomCtx, setModalState) {
              final textP = AppTheme.getTextPrimary(bottomCtx);
              final textS = AppTheme.getTextSecondary(bottomCtx);

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0070BA).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.payment_rounded, color: Color(0xFF0070BA), size: 28),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Ventana de PayPal Abierta',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textP),
                              ),
                              Text(
                                'Autoriza el cobro en la ventana emergente',
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
                        color: AppTheme.getBg(bottomCtx),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.getBorder(bottomCtx)),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Total en Bolivianos:', style: TextStyle(color: textS, fontSize: 13)),
                              Text('Bs. ${cart.total.toStringAsFixed(2)}', style: TextStyle(color: textP, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Equivalente a pagar:', style: TextStyle(color: textS, fontSize: 13)),
                              Text('\$ ${montoUsd.toStringAsFixed(2)} USD', style: const TextStyle(color: Color(0xFF0070BA), fontWeight: FontWeight.bold, fontSize: 14)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '1. Inicia sesión con tu cuenta Sandbox Personal en la ventana de PayPal.\n2. Presiona "Pay" para autorizar el cobro.\n3. Luego presiona el botón abajo para confirmar.',
                      style: TextStyle(color: textS, fontSize: 12, height: 1.4),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => UrlHelper.openUrl(approveUrl),
                      icon: const Icon(Icons.open_in_new_rounded, size: 16),
                      label: const Text('Abrir Ventana de PayPal', style: TextStyle(fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF0070BA),
                        side: const BorderSide(color: Color(0xFF0070BA)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: isCapturing
                          ? null
                          : () async {
                              setModalState(() => isCapturing = true);

                              final saleDetails = cart.items
                                  .map((i) => {
                                        'variante_id': i.variant.id,
                                        'cantidad': i.quantity,
                                        'precio_unitario': i.unitPrice,
                                      })
                                  .toList();

                              final capRes = await paypalService.captureOrder(
                                orderId: orderId,
                                sucursalId: cart.selectedBranch!.id,
                                detalles: saleDetails,
                                nota: 'Pago con PayPal Sandbox desde App Móvil',
                              );

                              setModalState(() => isCapturing = false);

                              if (!mounted) return;
                              if (capRes != null && capRes['venta'] != null) {
                                final venta = capRes['venta'] as Map<String, dynamic>;
                                final numRecibo = venta['numero_recibo'] ?? 'VTA-CONFIRMADA';
                                final captureId = capRes['paypal_capture_id'] ?? orderId;

                                cart.clearCart();
                                Navigator.pop(ctx); // Cierra bottom sheet

                                // Mostrar diálogo de confirmación oficial
                                await showDialog(
                                  context: context,
                                  barrierDismissible: false,
                                  builder: (dialogCtx) => AlertDialog(
                                    backgroundColor: AppTheme.getCardBg(dialogCtx),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(AppTheme.borderRadiusLarge),
                                    ),
                                    title: const Row(
                                      children: [
                                        Icon(Icons.check_circle_rounded, color: AppTheme.successColor, size: 28),
                                        SizedBox(width: 10),
                                        Text(
                                          '¡Pago con PayPal Exitoso!',
                                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                    content: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Tu compra ha sido cobrada y confirmada mediante PayPal Sandbox:',
                                          style: TextStyle(color: AppTheme.getTextSecondary(dialogCtx), fontSize: 13),
                                        ),
                                        const SizedBox(height: 12),
                                        Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: AppTheme.successColor.withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: AppTheme.successColor.withValues(alpha: 0.3)),
                                          ),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text('N° RECIBO: $numRecibo', style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.successColor, fontSize: 15)),
                                              const SizedBox(height: 4),
                                              Text('Transacción: PAYPAL_$captureId', style: TextStyle(color: AppTheme.getTextSecondary(dialogCtx), fontSize: 11)),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          'El stock de la tienda ha sido descontado y tu pedido está listo para despacho en la sucursal seleccionada.',
                                          style: TextStyle(color: AppTheme.getTextSecondary(dialogCtx), fontSize: 12),
                                        ),
                                      ],
                                    ),
                                    actions: [
                                      ElevatedButton(
                                        onPressed: () {
                                          Navigator.pop(dialogCtx);
                                          Navigator.pop(context); // Cierra CartScreen
                                        },
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFF0070BA),
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        ),
                                        child: const Text('Aceptar'),
                                      ),
                                    ],
                                  ),
                                );
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Aún no has autorizado el pago en la ventana de PayPal o hubo un problema al capturar.'),
                                    backgroundColor: AppTheme.errorColor,
                                  ),
                                );
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0070BA),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: isCapturing
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Text('Confirmar Pago Aprobado', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: isCapturing ? null : () => Navigator.pop(ctx),
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
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al conectar con PayPal: ${e.toString()}'),
            backgroundColor: AppTheme.errorColor,
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
    final cart = context.watch<CartService>();

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: cardBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        shape: Border(bottom: BorderSide(color: border)),
        title: Text(
          'Mi Carrito (${cart.totalItemCount})',
          style: TextStyle(
            color: textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          if (cart.items.isNotEmpty)
            TextButton.icon(
              onPressed: () => cart.clearCart(),
              icon: const Icon(Icons.delete_sweep_outlined, size: 18, color: AppTheme.errorColor),
              label: const Text(
                'Vaciar',
                style: TextStyle(color: AppTheme.errorColor, fontSize: 13),
              ),
            ),
        ],
      ),
      body: cart.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.shopping_bag_outlined,
                        size: 64,
                        color: accent,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Tu carrito está vacío',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Explora nuestro catálogo y agrega tus prendas favoritas para apartarlas.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: textSecondary),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.storefront_outlined),
                      label: const Text('Explorar Tienda'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Lista de prendas en el carrito
                ...cart.items.map((item) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
                      border: Border.all(color: border),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Icono o Imagen
                        Container(
                          width: 65,
                          height: 65,
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: item.product.imagenUrl != null && item.product.imagenUrl!.isNotEmpty
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    item.product.imagenUrl!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) => Icon(
                                      Icons.checkroom,
                                      color: accent,
                                    ),
                                  ),
                                )
                              : Icon(Icons.checkroom, color: accent),
                        ),
                        const SizedBox(width: 12),

                        // Detalles de la prenda
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.product.nombre,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: textPrimary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: accent.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      'Talla: ${item.variant.talla}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: accent,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: border.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      item.variant.color,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                        color: textSecondary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Bs. ${item.totalPrice.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: accent,
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.remove_circle_outline, size: 20),
                                        color: textSecondary,
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        onPressed: () => cart.updateQuantity(
                                          item.variant.id,
                                          item.quantity - 1,
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                        child: Text(
                                          '${item.quantity}',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                            color: textPrimary,
                                          ),
                                        ),
                                      ),
                                       IconButton(
                                         icon: Icon(
                                           Icons.add_circle_outline,
                                           size: 20,
                                           color: item.quantity < 3 ? accent : textSecondary.withValues(alpha: 0.4),
                                         ),
                                         padding: EdgeInsets.zero,
                                         constraints: const BoxConstraints(),
                                         onPressed: item.quantity < 3
                                             ? () => cart.updateQuantity(
                                                   item.variant.id,
                                                   item.quantity + 1,
                                                 )
                                             : () {
                                                 ScaffoldMessenger.of(context).showSnackBar(
                                                   const SnackBar(
                                                     content: Text('Máximo 3 unidades por prenda'),
                                                     duration: Duration(seconds: 1),
                                                     behavior: SnackBarBehavior.floating,
                                                   ),
                                                 );
                                               },
                                       ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }),

                const SizedBox(height: 12),

                // Selector de Sucursal Click & Collect
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
                    border: Border.all(color: border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.store_mall_directory_rounded, size: 20, color: accent),
                          const SizedBox(width: 8),
                          Text(
                            'Sucursal de Retiro (Click & Collect)',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: textPrimary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Elige en qué sede deseas apartar tus prendas para ir a recogerlas:',
                        style: TextStyle(fontSize: 12, color: textSecondary),
                      ),
                      const SizedBox(height: 12),
                      if (_isLoadingBranches)
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: CircularProgressIndicator(color: accent),
                          ),
                        )
                      else if (_branches.isEmpty)
                        Text(
                          'No hay sucursales disponibles en este momento',
                          style: TextStyle(color: textSecondary, fontSize: 12),
                        )
                      else
                        DropdownButtonFormField<String>(
                          initialValue: _branches.any((b) => b.id == cart.selectedBranch?.id)
                              ? cart.selectedBranch?.id
                              : (_branches.isNotEmpty ? _branches.first.id : null),
                          isExpanded: true,
                          dropdownColor: cardBg,
                          decoration: InputDecoration(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: border),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: border),
                            ),
                          ),
                          items: _branches.map((b) {
                            return DropdownMenuItem<String>(
                              value: b.id,
                              child: Text(
                                '${b.nombre} (${b.ciudad ?? "Santa Cruz"})',
                                style: TextStyle(
                                  color: textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            );
                          }).toList(),
                          onChanged: (newBranchId) {
                            if (newBranchId != null) {
                              final branch = _branches.firstWhere((b) => b.id == newBranchId);
                              cart.setSelectedBranch(branch);
                            }
                          },
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Resumen de Costo
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
                    border: Border.all(color: border),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Subtotal prendas', style: TextStyle(color: textSecondary, fontSize: 13)),
                          Text(
                            'Bs. ${cart.subtotal.toStringAsFixed(2)}',
                            style: TextStyle(color: textPrimary, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Costo de reserva', style: TextStyle(color: textSecondary, fontSize: 13)),
                          const Text(
                            'Bs. 0.00 (Gratis)',
                            style: TextStyle(color: AppTheme.successColor, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      Divider(height: 20, color: border),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Total a Pagar en Tienda',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: textPrimary),
                          ),
                          Text(
                            'Bs. ${cart.total.toStringAsFixed(2)}',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: accent),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Botón 1: Comprar Online Directo con PayPal
                ElevatedButton.icon(
                  onPressed: _isSubmitting ? null : _handleDirectPurchase,
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Icon(Icons.payment_rounded),
                  label: Text(
                    _isSubmitting ? 'Iniciando PayPal...' : 'Pagar Directo con PayPal',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0070BA),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                  ),
                ),

                const SizedBox(height: 12),

                // Botón 2: Apartar con Reserva Click & Collect
                OutlinedButton.icon(
                  onPressed: _isSubmitting ? null : _handleConfirmReservation,
                  icon: const Icon(Icons.bookmark_add_outlined),
                  label: const Text(
                    'Apartar con Reserva Click & Collect',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: accent,
                    side: BorderSide(color: accent),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),

                const SizedBox(height: 24),
              ],
            ),
    );
  }
}
