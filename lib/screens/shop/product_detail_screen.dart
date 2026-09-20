import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../models/product.dart';
import '../../models/product_variant.dart';
import '../../services/cart_service.dart';
import '../../services/inventory_service.dart';
import '../../services/product_service.dart';
import 'cart_screen.dart';
import 'virtual_fitting_screen.dart';
import '../virtual_tryon_screen.dart';

class ProductDetailScreen extends StatefulWidget {
  final String productId;

  const ProductDetailScreen({super.key, required this.productId});

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  Product? _product;
  bool _isLoading = true;
  String? _errorMessage;

  String? _selectedSize;
  String? _selectedColor;
  int _quantity = 1;

  // Disponibilidad por sucursal
  List<InventoryAvailability> _availability = [];
  bool _loadingAvailability = false;
  String? _lastVarianteId;

  @override
  void initState() {
    super.initState();
    _loadProduct();
  }

  Future<void> _loadProduct() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final service = context.read<ProductService>();
      final prod = await service.getProductById(widget.productId);
      if (mounted) {
        setState(() {
          _product = prod;
          _isLoading = false;
          if (prod != null && prod.variantes.isNotEmpty) {
            _selectedSize = prod.variantes.first.talla;
            _selectedColor = prod.variantes.first.color;
          }
        });
        // Load availability for first variant
        _loadAvailability();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error al cargar detalle: ${e.toString()}';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadAvailability() async {
    if (_product == null) return;
    // Use a cache key based on product + talla + color
    final cacheKey = '${_product!.id}:$_selectedSize:$_selectedColor';
    if (cacheKey == _lastVarianteId) return;
    setState(() {
      _loadingAvailability = true;
      _lastVarianteId = cacheKey;
    });
    try {
      final invService = context.read<InventoryService>();
      final list = await invService.getProductAvailability(
        productoId: _product!.id,
        talla: _selectedSize,
        color: _selectedColor,
      );
      if (mounted) {
        setState(() {
          _availability = list;
          _loadingAvailability = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingAvailability = false);
    }
  }

  List<String> get _availableSizes {
    if (_product == null) return [];
    final sizes = _product!.variantes.map((v) => v.talla).toSet().toList();
    sizes.sort();
    return sizes;
  }

  List<String> get _availableColorsForSize {
    if (_product == null) return [];
    if (_selectedSize == null) {
      return _product!.variantes.map((v) => v.color).toSet().toList();
    }
    return _product!.variantes
        .where((v) => v.talla == _selectedSize)
        .map((v) => v.color)
        .toSet()
        .toList();
  }

  ProductVariant? get _selectedVariant {
    if (_product == null || _product!.variantes.isEmpty) return null;
    try {
      return _product!.variantes.firstWhere(
        (v) => v.talla == _selectedSize && v.color == _selectedColor,
      );
    } catch (_) {
      // Fallback
      return _product!.variantes.first;
    }
  }

  double get _currentUnitPrice {
    if (_product == null) return 0.0;
    final variant = _selectedVariant;
    return _product!.precioBase + (variant?.precioAdicional ?? 0.0);
  }

  void _handleAddToCart() {
    final variant = _selectedVariant;
    if (_product == null || variant == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor selecciona una talla y un color válidos'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
      return;
    }

    final cart = context.read<CartService>();
    cart.addItem(_product!, variant, quantity: _quantity);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppTheme.successColor,
        behavior: SnackBarBehavior.floating,
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '¡${_product!.nombre} añadido al carrito!',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        action: SnackBarAction(
          label: 'VER CARRITO',
          textColor: Colors.white,
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CartScreen()),
            );
          },
        ),
      ),
    );
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

    if (_isLoading) {
      return Scaffold(
        backgroundColor: bg,
        appBar: AppBar(backgroundColor: cardBg, elevation: 0),
        body: Center(
          child: CircularProgressIndicator(color: accent),
        ),
      );
    }

    if (_errorMessage != null || _product == null) {
      return Scaffold(
        backgroundColor: bg,
        appBar: AppBar(backgroundColor: cardBg, elevation: 0),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppTheme.errorColor),
              const SizedBox(height: 16),
              Text(
                _errorMessage ?? 'Producto no encontrado',
                style: TextStyle(color: textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    final product = _product!;
    final variant = _selectedVariant;

    return Scaffold(
      backgroundColor: bg,
      body: CustomScrollView(
        slivers: [
          // Sliver App Bar con Imagen
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            backgroundColor: cardBg,
            elevation: 0,
            leading: Padding(
              padding: const EdgeInsets.all(8.0),
              child: CircleAvatar(
                backgroundColor: cardBg.withValues(alpha: 0.9),
                child: IconButton(
                  icon: Icon(Icons.arrow_back, color: textPrimary),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: CircleAvatar(
                  backgroundColor: cardBg.withValues(alpha: 0.9),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.shopping_bag_outlined),
                        color: textPrimary,
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const CartScreen()),
                          );
                        },
                      ),
                      if (cart.totalItemCount > 0)
                        Positioned(
                          top: 4,
                          right: 4,
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: const BoxDecoration(
                              color: AppTheme.accentColor,
                              shape: BoxShape.circle,
                            ),
                            constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                            child: Center(
                              child: Text(
                                '${cart.totalItemCount}',
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
                  ),
                ),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                color: accent.withValues(alpha: 0.08),
                child: product.imagenUrl != null && product.imagenUrl!.isNotEmpty
                    ? Image.network(
                        product.imagenUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (ctx, err, stack) => _buildPlaceholder(),
                      )
                    : _buildPlaceholder(),
              ),
            ),
          ),

          // Cuerpo de la pantalla
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Badges: Categoría y Temporada
                  Row(
                    children: [
                      if (product.categoriaNombre != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: accent.withValues(alpha: 0.3)),
                          ),
                          child: Text(
                            product.categoriaNombre!.toUpperCase(),
                            style: TextStyle(
                              color: accent,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      if (product.temporada != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: border),
                          ),
                          child: Text(
                            product.temporada!,
                            style: TextStyle(
                              color: textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Nombre del producto
                  Text(
                    product.nombre,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: textPrimary,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Precio
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        'Bs. ${_currentUnitPrice.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: accent,
                        ),
                      ),
                      if (variant != null && variant.precioAdicional > 0) ...[
                        const SizedBox(width: 8),
                        Text(
                          '(+Bs. ${variant.precioAdicional.toStringAsFixed(2)} por talla)',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),

                  // SKU Identificador
                  if (variant != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(AppTheme.borderRadiusSmall),
                        border: Border.all(color: border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.qr_code_2_rounded, size: 18, color: textSecondary),
                          const SizedBox(width: 6),
                          Text(
                            'SKU: ${variant.codigoSku}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 20),

                  // Descripción
                  if (product.descripcion != null && product.descripcion!.isNotEmpty) ...[
                    Text(
                      'Descripción',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      product.descripcion!,
                      style: TextStyle(
                        fontSize: 14,
                        color: textSecondary,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Selector de Tallas
                  if (_availableSizes.isNotEmpty) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Talla',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: textPrimary,
                              ),
                            ),
                            const SizedBox(width: 8),
                            InkWell(
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const VirtualFittingScreen(),
                                ),
                              ),
                              borderRadius: BorderRadius.circular(4),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                child: Row(
                                  children: [
                                    Icon(Icons.accessibility_new_rounded, size: 14, color: accent),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Guía de Tallas',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: accent,
                                        fontWeight: FontWeight.w600,
                                        decoration: TextDecoration.underline,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          'Seleccionada: ${_selectedSize ?? ""}',
                          style: TextStyle(fontSize: 13, color: accent, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: _availableSizes.map((size) {
                        final isSelected = _selectedSize == size;
                        return ChoiceChip(
                          label: Text(size),
                          selected: isSelected,
                          selectedColor: accent,
                          backgroundColor: cardBg,
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.white : textPrimary,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(
                              color: isSelected ? accent : border,
                            ),
                          ),
                          onSelected: (selected) {
                            if (selected) {
                              setState(() {
                                _selectedSize = size;
                                final validColors = _availableColorsForSize;
                                if (!validColors.contains(_selectedColor) && validColors.isNotEmpty) {
                                  _selectedColor = validColors.first;
                                }
                              });
                              _loadAvailability();
                            }
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Selector de Colores
                  if (_availableColorsForSize.isNotEmpty) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Color',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: textPrimary,
                          ),
                        ),
                        Text(
                          'Seleccionado: ${_selectedColor ?? ""}',
                          style: TextStyle(fontSize: 13, color: accent, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: _availableColorsForSize.map((color) {
                        final isSelected = _selectedColor == color;
                        return ChoiceChip(
                          label: Text(color),
                          selected: isSelected,
                          selectedColor: accent,
                          backgroundColor: cardBg,
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.white : textPrimary,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(
                              color: isSelected ? accent : border,
                            ),
                          ),
                          onSelected: (selected) {
                            if (selected) {
                              setState(() {
                                _selectedColor = color;
                              });
                              _loadAvailability();
                            }
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),
                  ],

                    // Botón Destacado: Vestidor Virtual con IA
                    Container(
                      margin: const EdgeInsets.only(bottom: 24),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: const LinearGradient(
                          colors: [Color(0xFF6C5CE7), Color(0xFF00CEC9)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF6C5CE7).withValues(alpha: 0.35),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            if (_product == null) return;
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => VirtualTryOnScreen(
                                  product: _product!,
                                ),
                              ),
                            );
                          },
                          borderRadius: BorderRadius.circular(16),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.2),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.auto_awesome,
                                    color: Colors.white,
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Vestidor Virtual',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 15,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                      SizedBox(height: 2),
                                      Text(
                                        'Pruébate esta prenda con tu foto usando Gemini',
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(
                                  Icons.arrow_forward_ios,
                                  color: Colors.white70,
                                  size: 16,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Disponibilidad por Sucursal
                    _buildAvailabilitySection(context),
                  const SizedBox(height: 24),

                  // Cantidad
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Cantidad',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: textPrimary,
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: border),
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove, size: 18),
                              color: textPrimary,
                              onPressed: _quantity > 1
                                  ? () => setState(() => _quantity--)
                                  : null,
                            ),
                            Text(
                              '$_quantity',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: textPrimary,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add, size: 18),
                              color: textPrimary,
                              onPressed: _quantity < 3
                                  ? () => setState(() => _quantity++)
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
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),

      // Barra inferior con Total y Botón de Añadir al Carrito
      bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: cardBg,
          border: Border(top: BorderSide(color: border)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: SafeArea(
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total a pagar',
                      style: TextStyle(fontSize: 11, color: textSecondary),
                    ),
                    Text(
                      'Bs. ${(_currentUnitPrice * _quantity).toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: accent,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 3,
                child: ElevatedButton.icon(
                  onPressed: _handleAddToCart,
                  icon: const Icon(Icons.add_shopping_cart_rounded, size: 18),
                  label: const Text(
                    'Añadir al Carrito',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Center(
      child: Icon(
        Icons.checkroom_rounded,
        size: 90,
        color: AppTheme.accentColor.withValues(alpha: 0.4),
      ),
    );
  }

  Widget _buildAvailabilitySection(BuildContext context) {
    final cardBg = AppTheme.getCardBg(context);
    final textPrimary = AppTheme.getTextPrimary(context);
    final textSecondary = AppTheme.getTextSecondary(context);
    final accent = AppTheme.getAccent(context);
    final border = AppTheme.getBorder(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Disponibilidad por sucursal',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: textPrimary),
            ),
            if (_loadingAvailability)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accentColor),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (!_loadingAvailability && _availability.isEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
              border: Border.all(color: border),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: textSecondary),
                const SizedBox(width: 8),
                Text(
                  'Selecciona talla y color para ver disponibilidad',
                  style: TextStyle(fontSize: 12, color: textSecondary),
                ),
              ],
            ),
          )
        else if (!_loadingAvailability)
          Container(
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
              border: Border.all(color: border),
            ),
            child: Column(
              children: _availability.asMap().entries.map((entry) {
                final i = entry.key;
                final avail = entry.value;
                final hasStock = avail.stockDisponible > 0;
                return Column(
                  children: [
                    if (i > 0) Divider(color: border, height: 1),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: hasStock ? AppTheme.successColor : AppTheme.errorColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  avail.sucursalNombre,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: textPrimary,
                                  ),
                                ),
                                if (avail.ciudad != null)
                                  Text(
                                    avail.ciudad!,
                                    style: TextStyle(fontSize: 11, color: textSecondary),
                                  ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                hasStock ? '${avail.stockDisponible} disp.' : 'Agotado',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: hasStock ? AppTheme.successColor : AppTheme.errorColor,
                                ),
                              ),
                              if (avail.stockReservado > 0)
                                Text(
                                  '${avail.stockReservado} reservado',
                                  style: TextStyle(fontSize: 10, color: accent),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        const SizedBox(height: 24),
      ],
    );
  }
}
