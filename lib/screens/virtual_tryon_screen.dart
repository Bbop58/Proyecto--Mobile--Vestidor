import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../config/theme.dart';
import '../models/product.dart';
import '../models/product_variant.dart';
import '../services/api_service.dart';
import '../services/ai_service.dart';
import '../services/cart_service.dart';
import 'shop/cart_screen.dart';

class VirtualTryOnScreen extends StatefulWidget {
  final Product product;
  final ProductVariant initialVariant;

  const VirtualTryOnScreen({
    super.key,
    required this.product,
    required this.initialVariant,
  });

  @override
  State<VirtualTryOnScreen> createState() => _VirtualTryOnScreenState();
}

class _VirtualTryOnScreenState extends State<VirtualTryOnScreen> {
  late ProductVariant _selectedVariant;
  Uint8List? _userImageBytes;
  String? _userImageBase64;
  bool _isProcessing = false;
  String _scanStepText = '';
  VirtualTryOnResult? _result;
  final ImagePicker _picker = ImagePicker();

  String _calcePreference = 'REGULAR';
  int _alturaCm = 175;
  int _pesoKg = 72;

  // Preset sample models for instant testing
  final List<Map<String, String>> _sampleModels = [
    {
      'label': 'Modelo 1 (Atlético)',
      'desc': '1.78m - 74kg',
      'url': 'https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?w=500&auto=format&fit=crop&q=80',
    },
    {
      'label': 'Modelo 2 (Casual)',
      'desc': '1.82m - 80kg',
      'url': 'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=500&auto=format&fit=crop&q=80',
    },
    {
      'label': 'Modelo 3 (Streetwear)',
      'desc': '1.72m - 68kg',
      'url': 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=500&auto=format&fit=crop&q=80',
    },
  ];

  @override
  void initState() {
    super.initState();
    _selectedVariant = widget.initialVariant;
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (photo != null) {
        final bytes = await photo.readAsBytes();
        setState(() {
          _userImageBytes = bytes;
          _userImageBase64 = base64Encode(bytes);
          _result = null;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo abrir la cámara o galería: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void _selectPresetModel(String url, String desc) {
    const dummyBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==";
    setState(() {
      _userImageBytes = null;
      _userImageBase64 = dummyBase64;
      _result = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Avatar seleccionado ($desc). ¡Listo para probar con IA!'),
        backgroundColor: const Color(0xFF6C5CE7),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _runVirtualTryOn() async {
    if (_userImageBase64 == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Primero toma una foto o selecciona un modelo de ejemplo.'),
          backgroundColor: Colors.orangeAccent,
        ),
      );
      return;
    }

    setState(() {
      _isProcessing = true;
      _scanStepText = '📸 Escaneando postura y proporciones corporales...';
    });

    final apiService = Provider.of<ApiService>(context, listen: false);
    final aiService = AIService(apiService);

    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted && _isProcessing) {
        setState(() => _scanStepText = '🧵 Analizando tejido y caída de tela en el torso...');
      }
    });

    Future.delayed(const Duration(milliseconds: 1400), () {
      if (mounted && _isProcessing) {
        setState(() => _scanStepText = '🧠 Google Gemini calculando talla ideal y calce...');
      }
    });

    final result = await aiService.requestVirtualTryOn(
      varianteId: _selectedVariant.id,
      imagenBase64: _userImageBase64!,
      alturaCm: _alturaCm,
      pesoKg: _pesoKg,
      preferenciaCalce: _calcePreference,
    );

    if (mounted) {
      setState(() {
        _isProcessing = false;
        _result = result;
      });

      if (result == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo conectar con el servicio de IA. Inténtalo de nuevo.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _addSuggestedSizeToCart() {
    if (_result == null) return;
    final suggestedSize = _result!.tallaSugerida;

    // Buscar variante que coincida con la talla sugerida y el color actual
    ProductVariant targetVariant = widget.product.variantes.firstWhere(
      (v) => v.talla.toUpperCase() == suggestedSize.toUpperCase() && v.color == _selectedVariant.color,
      orElse: () => widget.product.variantes.firstWhere(
        (v) => v.talla.toUpperCase() == suggestedSize.toUpperCase(),
        orElse: () => _selectedVariant,
      ),
    );

    final cart = Provider.of<CartService>(context, listen: false);
    cart.addItem(widget.product, targetVariant, quantity: 1);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('¡Añadido al carrito en Talla ${targetVariant.talla} (${targetVariant.color})!'),
        backgroundColor: Colors.green,
        action: SnackBarAction(
          label: 'Ver Carrito',
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
    const primaryColor = Color(0xFF6C5CE7);
    const darkBg = Color(0xFF0F111A);
    const cardBg = Color(0xFF1B1E2E);

    return Scaffold(
      backgroundColor: darkBg,
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.auto_awesome, color: Color(0xFFA29BFE), size: 20),
            SizedBox(width: 8),
            Text(
              'Vestidor Virtual con IA',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF131522),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header: Prenda seleccionada
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: primaryColor.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      widget.product.imagenUrl ?? '',
                      width: 60,
                      height: 60,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 60,
                        height: 60,
                        color: Colors.grey.shade800,
                        child: const Icon(Icons.checkroom, color: Colors.white70),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.product.nombre,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Color: ${_selectedVariant.color} | Talla Base: ${_selectedVariant.talla}',
                          style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${(widget.product.precioBase + _selectedVariant.precioAdicional).toStringAsFixed(2)} Bs.',
                          style: const TextStyle(
                            color: Color(0xFF00CEC9),
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Selector de Color/Variante
            if (widget.product.variantes.length > 1) ...[
              const Text(
                'Selecciona el Color a Probar:',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 38,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: widget.product.variantes.length,
                  itemBuilder: (context, index) {
                    final v = widget.product.variantes[index];
                    final isSelected = v.id == _selectedVariant.id;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text('${v.color} (${v.talla})'),
                        selected: isSelected,
                        selectedColor: primaryColor,
                        backgroundColor: cardBg,
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : Colors.grey.shade300,
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                        onSelected: (selected) {
                          if (selected) {
                            setState(() {
                              _selectedVariant = v;
                              _result = null;
                            });
                          }
                        },
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Visor Central: Foto / Espejo de Cámara
            Container(
              height: 300,
              decoration: BoxDecoration(
                color: const Color(0xFF151828),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _isProcessing
                      ? const Color(0xFF00CEC9)
                      : primaryColor.withOpacity(0.5),
                  width: 2,
                ),
              ),
              child: Stack(
                children: [
                  // Imagen o Silueta
                  Center(
                    child: _isProcessing
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00CEC9)),
                                strokeWidth: 3,
                              ),
                              const SizedBox(height: 20),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 24),
                                child: Text(
                                  _scanStepText,
                                  style: const TextStyle(
                                    color: Color(0xFF00CEC9),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          )
                        : _result != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(18),
                                child: Image.network(
                                  _result!.imagenResultadoUrl,
                                  width: double.infinity,
                                  height: double.infinity,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Icon(
                                    Icons.checkroom,
                                    color: Colors.white54,
                                    size: 80,
                                  ),
                                ),
                              )
                            : _userImageBytes != null
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(18),
                                    child: Image.memory(
                                      _userImageBytes!,
                                      width: double.infinity,
                                      height: double.infinity,
                                      fit: BoxFit.cover,
                                    ),
                                  )
                                : Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.person_outline,
                                        size: 80,
                                        color: primaryColor.withOpacity(0.6),
                                      ),
                                      const SizedBox(height: 12),
                                      const Text(
                                        'Tómate una foto o sube una imagen\npara verte con la prenda',
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 14,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                  ),

                  // Badge de Modo IA
                  Positioned(
                    top: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: primaryColor.withOpacity(0.6)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.bolt, color: Color(0xFFFFEAA7), size: 14),
                          const SizedBox(width: 4),
                          Text(
                            _result != null ? 'FICCT AI MATCH 97%' : 'ESPEJO VIRTUAL IA',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Botones para tomar foto / elegir
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isProcessing ? null : () => _pickImage(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Tomar Foto'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: cardBg,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey.shade700),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isProcessing ? null : () => _pickImage(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Galería'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: cardBg,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey.shade700),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Avatares de Prueba Rápida
            const Text(
              'O prueba con un modelo de ejemplo:',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Row(
              children: _sampleModels.map((model) {
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: OutlinedButton(
                      onPressed: _isProcessing
                          ? null
                          : () => _selectPresetModel(model['url']!, model['desc']!),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: cardBg,
                        side: BorderSide(color: Colors.grey.shade800),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(
                        model['label']!.split(' ').first,
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 20),

            // Botón Principal de Procesamiento con IA
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(
                  colors: [Color(0xFF6C5CE7), Color(0xFF00CEC9)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: primaryColor.withOpacity(0.4),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ElevatedButton.icon(
                onPressed: _isProcessing ? null : _runVirtualTryOn,
                icon: const Icon(Icons.auto_awesome, color: Colors.white),
                label: Text(
                  _isProcessing ? 'PROCESANDO CON IA...' : 'PROBARME ESTA PRENDA CON IA',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    letterSpacing: 0.5,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Tarjeta de Resultados Inteligentes de Talla y Calce
            if (_result != null) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF00CEC9), width: 1.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.check_circle, color: Color(0xFF00CEC9), size: 22),
                            SizedBox(width: 8),
                            Text(
                              'Asesoría de Talla Inteligente',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00CEC9).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${_result!.nivelCoincidenciaPorcentaje}% Match',
                            style: const TextStyle(
                              color: Color(0xFF00CEC9),
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Divider(color: Colors.white24, height: 24),

                    // Talla Sugerida
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: primaryColor,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'TALLA ${_result!.tallaSugerida}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Calce Recomendado:',
                                style: TextStyle(color: Colors.white70, fontSize: 12),
                              ),
                              Text(
                                _result!.calceDetectado,
                                style: const TextStyle(
                                  color: Color(0xFFFFEAA7),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Análisis de Silueta
                    Text(
                      _result!.analisisSilueta,
                      style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                    ),

                    const SizedBox(height: 12),

                    // Consejo de Estilo
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.tips_and_updates, color: Color(0xFFFFEAA7), size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _result!.consejoEstilo,
                              style: const TextStyle(color: Colors.white, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Botón para Añadir la Talla Sugerida al Carrito
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _addSuggestedSizeToCart,
                        icon: const Icon(Icons.shopping_bag_outlined),
                        label: Text(
                          'AÑADIR TALLA ${_result!.tallaSugerida} AL CARRITO',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00CEC9),
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Combinaciones Sugeridas de Catálogo
              if (_result!.combinacionesSugeridas.isNotEmpty) ...[
                const Text(
                  'Completa tu Outfit FICCT STORE:',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 10),
                Column(
                  children: _result!.combinacionesSugeridas.map((item) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.style, color: Color(0xFFA29BFE), size: 24),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.nombre,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  item.motivo,
                                  style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ],
            ],

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
