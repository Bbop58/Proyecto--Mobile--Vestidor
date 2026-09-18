import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../models/category.dart';
import '../../models/product.dart';
import '../../services/cart_service.dart';
import '../../services/category_service.dart';
import '../../services/product_service.dart';
import '../../services/season_service.dart';
import 'cart_screen.dart';
import 'product_detail_screen.dart';
import 'virtual_fitting_screen.dart';

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
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final catService = context.read<CategoryService>();
      final seasonService = context.read<SeasonService>();
      final prodService = context.read<ProductService>();

      final categories = await catService.getCategories();
      final seasons = await seasonService.getSeasons();

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

      if (mounted) {
        setState(() {
          _categories = categories;
          _seasons = seasons;
          _products = products;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error al cargar el catálogo: ${e.toString()}';
          _isLoading = false;
        });
      }
    }
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
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: AppTheme.logoBadgeDecorationOf(context),
              child: const Icon(Icons.storefront_rounded, size: 20, color: AppTheme.accentColor),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'FICCT STORE',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: textPrimary,
                  ),
                ),
                Text(
                  'Catálogo & Compras',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
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
              height: 44,
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
                height: 40,
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
                                    foregroundColor: Colors.white,
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
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                childAspectRatio: 0.72,
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
                  color: isSelected ? Colors.white : textSecondary,
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

  Widget _buildProductCard(BuildContext context, Product product) {
    final cardBg = AppTheme.getCardBg(context);
    final textPrimary = AppTheme.getTextPrimary(context);
    final border = AppTheme.getBorder(context);
    final accent = AppTheme.getAccent(context);

    return Container(
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
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ProductDetailScreen(productId: product.id),
              ),
            );
          },
          borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Imagen del producto o contenedor con icono estilizado
              Expanded(
                flex: 5,
                child: Stack(
                  children: [
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.08),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(AppTheme.borderRadiusMedium),
                        ),
                      ),
                      child: product.imagenUrl != null && product.imagenUrl!.isNotEmpty
                          ? ClipRRect(
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(AppTheme.borderRadiusMedium),
                              ),
                              child: Image.network(
                                product.imagenUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (ctx, err, stack) => _buildPlaceholderImage(accent),
                              ),
                            )
                          : _buildPlaceholderImage(accent),
                    ),
                    if (product.temporada != null && product.temporada!.isNotEmpty)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            product.temporada!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // Información del producto
              Expanded(
                flex: 4,
                child: Padding(
                  padding: const EdgeInsets.all(10.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (product.categoriaNombre != null)
                            Text(
                              product.categoriaNombre!.toUpperCase(),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: accent,
                                letterSpacing: 0.5,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          const SizedBox(height: 2),
                          Text(
                            product.nombre,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: textPrimary,
                              height: 1.2,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            'Bs. ${product.precioBase.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: accent,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 11,
                              color: accent,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholderImage(Color accent) {
    return Center(
      child: Icon(
        Icons.checkroom_rounded,
        size: 48,
        color: accent.withValues(alpha: 0.4),
      ),
    );
  }
}
