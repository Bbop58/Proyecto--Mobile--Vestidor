import 'package:flutter/material.dart';

import '../config/theme.dart';

/// Stack price and action on narrow screens or when accessibility text grows.
class PurchaseSummaryBar extends StatelessWidget {
  final double total;
  final VoidCallback onAdd;
  const PurchaseSummaryBar({
    super.key,
    required this.total,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final price = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Total a pagar',
                style: TextStyle(
                  color: AppTheme.getTextSecondary(context),
                  fontSize: 13,
                ),
              ),
              Text(
                'Bs. ${total.toStringAsFixed(2)}',
                style: TextStyle(
                  color: AppTheme.getTextPrimary(context),
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          );
          final action = ElevatedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_shopping_cart_rounded, size: 20),
            label: const Text('Añadir al Carrito'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(0, 48),
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            ),
          );
          if (constraints.maxWidth < 380 ||
              MediaQuery.textScalerOf(context).scale(16) > 21) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [price, const SizedBox(height: 12), action],
            );
          }
          return Row(
            children: [
              Expanded(child: price),
              const SizedBox(width: 16),
              Expanded(child: action),
            ],
          );
        },
      ),
    ),
  );
}
