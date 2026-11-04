import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../models/category.dart';
import '../../models/product.dart';
import '../../models/product_variant.dart';
import '../../core/database/database_helper.dart';
import '../../core/services/connectivity_service.dart';
import '../../services/cart_service.dart';
import '../../services/category_service.dart';
import '../../services/product_service.dart';
import '../../services/season_service.dart';
import '../../services/notification_service.dart';
import 'cart_screen.dart';
import '../../widgets/shop_product_tile.dart';
import 'product_detail_screen.dart';
import 'virtual_fitting_screen.dart';
import 'favorites_screen.dart';
import '../../services/favorite_service.dart';
import '../notifications/notifications_screen.dart';


class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key});

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Category> _categories = [];
  List<Season> _seasons = [];
  List<Product> _products = [];
  String? _selectedCategoryId;
  String? _selectedSeasonId;
  int _generation=0;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final owner=DatabaseHelper.scope;
    if(owner==null) return;
    final generation=++_generation;
    final db=DatabaseHelper.instance.forScope(owner);
    bool current()=>mounted && owner==DatabaseHelper.scope && generation==_generation;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final connectivity = context.read<ConnectivityService>();
    final catService = context.read<CategoryService>();
    final seasonService = context.read<SeasonService>();
    final prodService = context.read<ProductService>();
    final notifService = context.read<NotificationService>();

    if (!connectivity.isOnline) {
      final loadedOffline = await _loadFromSqliteCache(owner,generation);
      if (loadedOffline) return;
    }

    try {
      notifService.fetchUnreadCount();

      final categories = await catService.getCategories();
      if(!current()) return;
      final seasons = await seasonService.getSeasons();
      if(!current()) return;

      // Obtener el nombre de temporada seleccionada para el filtro
      String? selectedSeasonName;
      if (_selectedSeasonId != null) {
        final found = seasons.where((s) => s.id == _selectedSeasonId);
        if (found.isNotEmpty) selectedSeasonName = found.first.nombre;
      }

      final products = await prodService.getProducts(
        categoriaId: _selectedCategoryId,
        temporada: selectedSeasonName,
        search: _searchController.text.trim().isNotEmpty
            ? _searchController.text.trim()
            : null,
      );

      if(!current()) return;
      final fullCatalog=_selectedCategoryId==null && _selectedSeasonId==null && _searchController.text.trim().isEmpty;

      // Cachear en SQLite local solo cuando hay productos válidos
      if (fullCatalog) {
        try {
          await db.cacheProducts(products.map((p) => {
            'id': p.id,
            'nombre': p.nombre,
            'categoria': p.categoriaNombre ?? '',
            'categoria_id':p.categoriaId,
            'temporada':p.temporada,
            'precio_base': p.precioBase,
            'precio_oferta': p.precioOferta,
            'en_oferta': p.enOferta ? 1 : 0,
            'imagen_url': p.imagenUrl ?? '',
            'variantes_json': jsonEncode(p.variantes.map((v) => {
              'id': v.id,
              'producto_id': v.productoId,
              'sku': v.codigoSku,
              'talla': v.talla,
              'color': v.color,
              'precio_extra': v.precioAdicional,
              'imagen_url': v.imagenUrl,
            }).toList()),
          }).toList(),replace:true);
        } catch (e) {
          debugPrint('Error al guardar caché en SQLite: $e');
        }
      }

      if (current()) {
        setState(() {
          _categories = categories;
          _seasons = seasons;
          _products = products;
          _isLoading = false;
        });
      }
    } catch (e) {
      if(!current()) return;
      // Fallback: cargar catálogo desde la base de datos local SQLite
      final loadedOffline = await _loadFromSqliteCache(owner,generation);
      if (!loadedOffline && mounted) {
        setState(() {
          _errorMessage = 'Modo offline: No hay productos en la caché local para mostrar.';
          _isLoading = false;
        });
      }
    }
  }

  /// Carga de emergencia o contingencia offline desde SQLite local
  Future<bool> _loadFromSqliteCache(String owner,int generation) async {
    if(owner!=DatabaseHelper.scope || generation!=_generation) return false;
    try {
      final cached = await DatabaseHelper.instance.forScope(owner).getCachedProducts();
      if(!mounted || owner!=DatabaseHelper.scope || generation!=_generation) return false;
      if (cached.isNotEmpty) {
        final fallbackProducts = cached.map((c) {
          List<ProductVariant> vars = [];
          try {
            final rawV = jsonDecode(c['variantes_json'] as String) as List;
            vars = rawV.map((v) => ProductVariant(
              id: v['id'] ?? '',
              productoId: (v['producto_id'] ?? c['id'] ?? '').toString(),
              talla: v['talla'] ?? '',
              color: v['color'] ?? '',
              codigoSku: v['sku'] ?? '',
              precioAdicional: (v['precio_extra'] as num?)?.toDouble() ?? 0.0,
              imagenUrl: v['imagen_url'] as String?,
              activo: true,
            )).toList();
          } catch (_) {}

          return Product(
            id: c['id'] as String,
            codigo: (c['id'] as String).length >= 8 ? (c['id'] as String).substring(0, 8).toUpperCase() : (c['id'] as String),
            nombre: c['nombre'] as String,
            precioBase: (c['precio_base'] as num).toDouble(),
            precioOferta: (c['precio_oferta'] as num?)?.toDouble(),
            enOferta: (c['en_oferta'] == 1 || c['en_oferta'] == true),
            categoriaNombre: c['categoria'] as String?,
            categoriaId:c['categoria_id'] as String?,
            temporada:c['temporada'] as String?,
            imagenUrl: c['imagen_url'] as String?,
            activo: true,
            variantes: vars,
          );
        }).toList();

        // Aplicar filtro de búsqueda si el usuario ingresó texto
        final query = _searchController.text.trim().toLowerCase();
        final selectedSeasons=_seasons.where((s)=>s.id==_selectedSeasonId).toList();
        final filtered=fallbackProducts.where((p)=>
          (_selectedCategoryId==null || p.categoriaId==_selectedCategoryId) &&
          (_selectedSeasonId==null || (selectedSeasons.isNotEmpty && p.temporada==selectedSeasons.first.nombre)) &&
          (query.isEmpty || p.nombre.toLowerCase().contains(query) || (p.categoriaNombre?.toLowerCase().contains(query) ?? false))).toList();

        if (mounted) {
          setState(() {
            _products = filtered;
            _isLoading = false;
            _errorMessage = null;
          });
          return true;
        }
      }
    } catch (e) {
      debugPrint('[CATALOG] Error leyendo respaldo SQLite: $e');
    }
    return false;
  }

  void _onCategorySelected(String? categoryId) {
    setState(() {
      _selectedCategoryId = categoryId;
    });
    _loadData();
  }

  void _onSeasonSelected(String? seasonId) {
    setState(() {
      _selectedSeasonId = seasonId;
    });
    _loadData();
  }

  void _onSearchSubmitted(String query) {
    _loadData();
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
        title: Text('Catálogo', maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: textPrimary)),
        actions: [
          // Bell Icon con Badge de Notificaciones
          Consumer<NotificationService>(
            builder: (context, notifService, _) {
              final count = notifService.unreadCount;
              return Stack(
                alignment: Alignment.center,
                children: [
                  IconButton(
                    icon: Icon(
                      count > 0 ? Icons.notifications_active_rounded : Icons.notifications_outlined,
                      size: 22,
                    ),
                    color: count > 0 ? accent : textPrimary,
                    tooltip: 'Notificaciones',
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                      );
                    },
                  ),
                  if (count > 0)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          color: AppTheme.errorColor,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                        child: Center(
                          child: Text(
                            count > 9 ? '9+' : '$count',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          // Wishlist / Favoritos Button
          Consumer<FavoriteService>(
            builder: (context, favService, _) {
              final count = favService.count;
              return Stack(
                alignment: Alignment.center,
                children: [
                  IconButton(
                    icon: Icon(
                      count > 0 ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      size: 22,
                    ),
                    color: count > 0 ? Colors.red : textPrimary,
                    tooltip: 'Mis Favoritos',
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const FavoritesScreen()),
                      );
                    },
                  ),
                  if (count > 0)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                        child: Center(
                          child: Text(
                            count > 9 ? '9+' : '$count',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.shopping_bag_outlined),
                color: textPrimary,
                tooltip: 'Ver Carrito',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CartScreen()),
                  );
                },
              ),
              if (cart.totalItemCount > 0)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: AppTheme.accentColor,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                    child: Center(
                      child: Text(
                        '${cart.totalItemCount}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        color: accent,
        onRefresh: _loadData,
        child: Column(
          children: [
            // Barra de búsqueda
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              color: bg,
              child: Container(
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
                  border: Border.all(color: border),
                ),
                child: TextField(
                  controller: _searchController,
                  onSubmitted: _onSearchSubmitted,
                  textInputAction: TextInputAction.search,
                  style: TextStyle(color: textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Buscar prendas, poleras, jeans...',
                    hintStyle: TextStyle(color: textSecondary, fontSize: 13),
                    prefixIcon: Icon(Icons.search, color: textSecondary, size: 20),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.clear, color: textSecondary, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              _loadData();
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ),
            ),

            // Filtro horizontal de categorías
            Container(
              height: 48 + (MediaQuery.textScalerOf(context).scale(16) - 16),
              margin: const EdgeInsets.only(bottom: 4),
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _buildCategoryChip(
                    label: 'Todos',
                    isSelected: _selectedCategoryId == null,
                    onTap: () => _onCategorySelected(null),
                  ),
                  ..._categories.map(
                    (cat) => _buildCategoryChip(
                      label: cat.nombre,
                      isSelected: _selectedCategoryId == cat.id,
                      onTap: () => _onCategorySelected(cat.id),
                    ),
                  ),
                ],
              ),
            ),

            // Filtro horizontal de temporadas
            if (_seasons.isNotEmpty)
              Container(
                height: 48 + (MediaQuery.textScalerOf(context).scale(16) - 16),
                margin: const EdgeInsets.only(bottom: 8),
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    _buildSeasonChip(
                      label: 'Todas temporadas',
                      isSelected: _selectedSeasonId == null,
                      onTap: () => _onSeasonSelected(null),
                    ),
                    ..._seasons.map(
                      (s) => _buildSeasonChip(
                        label: s.nombre,
                        isSelected: _selectedSeasonId == s.id,
                        onTap: () => _onSeasonSelected(s.id),
                      ),
                    ),
                    // Botón acceso rápido al vestidor virtual
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: InkWell(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const VirtualFittingScreen()),
                        ),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppTheme.getCardBg(context),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AppTheme.getBorder(context)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.straighten_rounded,
                                  size: 14, color: AppTheme.getTextSecondary(context)),
                              const SizedBox(width: 4),
                              Text('Guía de tallas',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.getTextSecondary(context),
                                      fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Contenido: Lista / Grid de Productos
            Expanded(
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
                                  onPressed: _loadData,
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('Reintentar'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: accent,
                                    foregroundColor: AppTheme.onAccent(context),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : _products.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.inventory_2_outlined, size: 64, color: textSecondary.withValues(alpha: 0.5)),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No se encontraron productos',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Prueba con otra categoría o término de búsqueda',
                                    style: TextStyle(fontSize: 13, color: textSecondary),
                                  ),
                                ],
                              ),
                            )
                          : GridView.builder(
                              padding: const EdgeInsets.all(16),
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: _catalogColumns(context),
                                mainAxisExtent: _catalogTileHeight(context),
                                crossAxisSpacing: 14,
                                mainAxisSpacing: 14,
                              ),
                              itemCount: _products.length,
                              itemBuilder: (context, index) {
                                final product = _products[index];
                                return _buildProductCard(context, product);
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final accent = AppTheme.getAccent(context);
    final cardBg = AppTheme.getCardBg(context);
    final textSecondary = AppTheme.getTextSecondary(context);
    final border = AppTheme.getBorder(context);

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected ? accent : cardBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: isSelected ? accent : border),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.3),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      )
                    ]
                  : null,
            ),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected ? AppTheme.onAccent(context) : textSecondary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSeasonChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final cardBg = AppTheme.getCardBg(context);
    final textSecondary = AppTheme.getTextSecondary(context);
    final border = AppTheme.getBorder(context);
    final seasonColor = const Color(0xFF7C3AED); // Violet para temporadas

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isSelected ? seasonColor : cardBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: isSelected ? seasonColor : border.withValues(alpha: 0.5)),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: seasonColor.withValues(alpha: 0.3),
                        blurRadius: 5,
                        offset: const Offset(0, 2),
                      )
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.calendar_month_rounded,
                  size: 12,
                  color: isSelected ? Colors.white : textSecondary,
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: isSelected ? Colors.white : textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  int _catalogColumns(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final large = MediaQuery.textScalerOf(context).scale(16) > 21;
    return width < 380 || large ? 1 : (width >= 900 ? 3 : 2);
  }

  double _catalogTileHeight(BuildContext context) {
    final columns = _catalogColumns(context);
    final width = (MediaQuery.sizeOf(context).width - 32 - (columns - 1) * 12) / columns;
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    return width * 1.15 + 145 * scale;
  }

  Widget _buildProductCard(BuildContext context, Product product) {
    return Consumer<FavoriteService>(builder: (context, favorites, _) => ShopProductTile(
      product: product,
      isFavorite: favorites.isFavorite(product.id),
      onFavorite: () => favorites.toggleFavorite(product),
      onOpen: () => Navigator.push(context, MaterialPageRoute(
        builder: (_) => ProductDetailScreen(productId: product.id))),
    ));
  }
}
