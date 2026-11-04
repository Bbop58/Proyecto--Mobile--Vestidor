import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../models/product.dart';

/// Product-first tile: the text grows naturally instead of sharing a fixed flex.
class ShopProductTile extends StatelessWidget {
  final Product product;
  final bool isFavorite;
  final VoidCallback onOpen;
  final VoidCallback onFavorite;
  const ShopProductTile({
    super.key,
    required this.product,
    required this.isFavorite,
    required this.onOpen,
    required this.onFavorite,
  });

  @override
  Widget build(BuildContext context) {
    final text = AppTheme.getTextPrimary(context);
    final muted = AppTheme.getTextSecondary(context);
    return Material(
      color: AppTheme.getCardBg(context),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: AppTheme.getBorder(context)),
      ),
      child: InkWell(
        onTap: onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(
                    color: AppTheme.getInputBg(context),
                    child: product.imagenUrl?.isNotEmpty == true
                        ? Image.network(
                            product.imagenUrl!,
                            fit: BoxFit.cover,
                            excludeFromSemantics: true,
                            errorBuilder: (_, error, stack) => Icon(
                              Icons.checkroom_rounded,
                              size: 64,
                              color: muted,
                            ),
                          )
                        : Icon(Icons.checkroom_rounded, size: 64, color: muted),
                  ),
                  if (product.enOferta)
                    Positioned(
                      top: 12,
                      left: 12,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0xFF991B1B),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          child: Text(
                            product.porcentajeDescuento > 0
                                ? '-${product.porcentajeDescuento}%'
                                : 'Oferta',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Material(
                      color: AppTheme.getCardBg(context),
                      borderRadius: BorderRadius.circular(30),
                      child: IconButton(
                        onPressed: onFavorite,
                        tooltip: isFavorite
                            ? 'Quitar de favoritos'
                            : 'Añadir a favoritos',
                        isSelected: isFavorite,
                        icon: const Icon(Icons.favorite_border_rounded),
                        selectedIcon: const Icon(Icons.favorite_rounded),
                        color: text,
                        constraints: const BoxConstraints(
                          minWidth: 48,
                          minHeight: 48,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (product.categoriaNombre?.isNotEmpty == true)
                    Text(
                      product.categoriaNombre!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: muted, fontSize: 12),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    product.nombre,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: text,
                      fontSize: 15,
                      height: 1.25,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Bs. ${product.precioEfectivo.toStringAsFixed(2)}',
                    style: TextStyle(
                      color: text,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (product.enOferta)
                    Text(
                      'Antes Bs. ${product.precioBase.toStringAsFixed(2)}',
                      style: TextStyle(
                        color: muted,
                        fontSize: 12,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
