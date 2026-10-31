import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../core/services/connectivity_service.dart';
import '../../services/favorite_service.dart';
import 'product_detail_screen.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) {
        context.read<FavoriteService>().fetchFavorites();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final favService = context.watch<FavoriteService>();
    final connectivity = context.watch<ConnectivityService>();
    final favorites = favService.favorites;

    final bg = AppTheme.getBg(context);
    final cardBg = AppTheme.getCardBg(context);
    final border = AppTheme.getBorder(context);
    final textP = AppTheme.getTextPrimary(context);
    final textS = AppTheme.getTextSecondary(context);
    final accent = AppTheme.getAccent(context);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: const Text('Mis Favoritos', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
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
        ],
      ),
      body: favService.isLoading && favorites.isEmpty
          ? Center(child: CircularProgressIndicator(color: accent))
          : favorites.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.favorite_border_rounded, size: 64, color: textS.withValues(alpha: 0.5)),
                        const SizedBox(height: 16),
                        Text(
                          'No tienes prendas favoritas',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textP),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Toca el ícono de corazón en cualquier prenda del catálogo para guardarla en tu lista personal y revisarla cuando quieras.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: textS, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: favorites.length,
                  itemBuilder: (context, index) {
                    final product = favorites[index];
                    final enOferta = product.enOferta;
                    final precioActivo = product.precioEfectivo;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: border),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ProductDetailScreen(productId: product.id),
                            ),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  width: 70,
                                  height: 70,
                                  color: Colors.grey.withValues(alpha: 0.1),
                                  child: product.imagenUrl != null && product.imagenUrl!.isNotEmpty
                                      ? Image.network(
                                          product.imagenUrl!,
                                          fit: BoxFit.cover,
                                          errorBuilder: (ctx, err, stack) => const Icon(Icons.checkroom, color: Colors.grey),
                                        )
                                      : const Icon(Icons.checkroom, color: Colors.grey),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (enOferta)
                                      Container(
                                        margin: const EdgeInsets.only(bottom: 4),
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.red.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                                        ),
                                        child: Text(
                                          'OFERTA -${product.porcentajeDescuento}%',
                                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red),
                                        ),
                                      ),
                                    Text(
                                      product.nombre,
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: textP),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      product.categoriaNombre ?? 'Prenda',
                                      style: TextStyle(color: textS, fontSize: 12),
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        Text(
                                          'Bs. ${precioActivo.toStringAsFixed(2)}',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                            color: enOferta ? Colors.red : accent,
                                          ),
                                        ),
                                        if (enOferta) ...[
                                          const SizedBox(width: 8),
                                          Text(
                                            'Bs. ${product.precioBase.toStringAsFixed(2)}',
                                            style: TextStyle(
                                              decoration: TextDecoration.lineThrough,
                                              color: textS,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.favorite_rounded, color: Colors.red),
                                tooltip: 'Quitar de favoritos',
                                onPressed: () async {
                                  await favService.toggleFavorite(product);
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
