import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/product.dart';
import '../models/product_variant.dart';
import '../services/api_service.dart';
import '../services/ai_service.dart';

class VirtualTryOnScreen extends StatefulWidget {
  final Product product;
  final ProductVariant? initialVariant;

  const VirtualTryOnScreen({
    super.key,
    required this.product,
    this.initialVariant,
  });

  @override
  State<VirtualTryOnScreen> createState() => _VirtualTryOnScreenState();
}

class _VirtualTryOnScreenState extends State<VirtualTryOnScreen> {
  final ImagePicker _picker = ImagePicker();

  Uint8List? _userImageBytes;
  String? _userImageBase64;
  bool _isLoading = false;
  String? _generatedImageBase64;
  String? _errorMessage;

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
          _errorMessage = null;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'No se pudo acceder a la cámara o galería: $e';
      });
    }
  }

  Future<void> _generateTryOn() async {
    if (_userImageBase64 == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor, toma una foto o elige una de tu galería.'),
          backgroundColor: Colors.orangeAccent,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final aiService = AIService(apiService);

      final result = await aiService.generateVirtualTryOn(
        productoId: widget.product.id,
        imagenBase64: _userImageBase64!,
      );

      if (mounted) {
        setState(() {
          _generatedImageBase64 = result;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  void _resetToTryAgain() {
    setState(() {
      _generatedImageBase64 = null;
      _errorMessage = null;
    });
  }

  void _handleShareOrSave() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('¡Imagen lista para compartir o guardar!'),
        backgroundColor: Color(0xFF6C5CE7),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Widget _buildDecodedImage(String base64OrDataUri) {
    try {
      String cleanBase64 = base64OrDataUri;
      if (base64OrDataUri.contains('base64,')) {
        cleanBase64 = base64OrDataUri.split('base64,').last;
      }
      final bytes = base64Decode(cleanBase64.trim());
      return Image.memory(
        bytes,
        fit: BoxFit.contain,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, _, _) => const Center(
          child: Text(
            'Error al visualizar la imagen generada',
            style: TextStyle(color: Colors.white70),
          ),
        ),
      );
    } catch (e) {
      return Center(
        child: Text(
          'Error al procesar la imagen: $e',
          style: const TextStyle(color: Colors.white70),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF6C5CE7);
    const darkBg = Color(0xFF0F111A);
    const cardBg = Color(0xFF1B1E2E);

    // ==========================================
    // VISTA 1: RESULTADO EN PANTALLA COMPLETA
    // ==========================================
    if (_generatedImageBase64 != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Imagen generada a pantalla completa
            Center(
              child: _buildDecodedImage(_generatedImageBase64!),
            ),

            // Barra superior traslúcida con botón de cerrar
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top + 8,
                  left: 16,
                  right: 16,
                  bottom: 16,
                ),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.black87, Colors.transparent],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white, size: 28),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Tu Vestidor Virtual',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Barra inferior traslúcida con acciones: Volver a intentar y Guardar/Compartir
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).padding.bottom + 16,
                  left: 20,
                  right: 20,
                  top: 20,
                ),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.transparent, Colors.black87, Colors.black],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _resetToTryAgain,
                        icon: const Icon(Icons.refresh, color: Colors.white),
                        label: const Text(
                          'Volver a intentar',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.white54),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _handleShareOrSave,
                        icon: const Icon(Icons.share, color: Colors.white),
                        label: const Text(
                          'Guardar / Compartir',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    // ==========================================
    // VISTA 2: PANTALLA PRINCIPAL DE CAPTURA
    // ==========================================
    return Scaffold(
      backgroundColor: darkBg,
      appBar: AppBar(
        title: const Text(
          'Vestidor Virtual',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: const Color(0xFF131522),
        elevation: 0,
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00CEC9)),
                    strokeWidth: 3.5,
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Generando tu prueba virtual...',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Gemini está adaptando la prenda a tu foto de forma realista',
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Prenda a probar (Referencia fija del producto actual)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: primaryColor.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: (widget.product.imagenUrl != null &&
                                  widget.product.imagenUrl!.isNotEmpty)
                              ? Image.network(
                                  widget.product.imagenUrl!,
                                  width: 65,
                                  height: 65,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => Container(
                                    width: 65,
                                    height: 65,
                                    color: Colors.grey.shade800,
                                    child: const Icon(Icons.checkroom, color: Colors.white70),
                                  ),
                                )
                              : Container(
                                  width: 65,
                                  height: 65,
                                  color: Colors.grey.shade800,
                                  child: const Icon(Icons.checkroom, color: Colors.white70),
                                ),
                        ),
                        const SizedBox(width: 14),
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
                                'Prenda a probar',
                                style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${widget.product.precioBase.toStringAsFixed(2)} Bs.',
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

                  const SizedBox(height: 24),

                  // Mensaje de Error simple en español si la IA falló
                  if (_errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.red.shade900.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.6)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: Colors.redAccent, size: 24),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: const TextStyle(color: Colors.white, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Área de previsualización o toma de foto
                  Container(
                    height: 340,
                    decoration: BoxDecoration(
                      color: const Color(0xFF151828),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _userImageBytes != null
                            ? primaryColor
                            : Colors.white12,
                        width: 1.5,
                      ),
                    ),
                    child: _userImageBytes != null
                        ? Stack(
                            fit: StackFit.expand,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(18),
                                child: Image.memory(
                                  _userImageBytes!,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              Positioned(
                                top: 12,
                                right: 12,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.7),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: IconButton(
                                    icon: const Icon(Icons.refresh, color: Colors.white, size: 20),
                                    tooltip: 'Cambiar foto',
                                    onPressed: () => setState(() {
                                      _userImageBytes = null;
                                      _userImageBase64 = null;
                                      _errorMessage = null;
                                    }),
                                  ),
                                ),
                              ),
                            ],
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.person_outline,
                                size: 80,
                                color: primaryColor.withValues(alpha: 0.6),
                              ),
                              const SizedBox(height: 16),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 24),
                                child: Text(
                                  'Tómate una foto o sube una desde tu galería para verte con la prenda puesta',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 14,
                                    height: 1.4,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                  ),

                  const SizedBox(height: 20),

                  // Botones de Selección: Cámara o Galería
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _pickImage(ImageSource.camera),
                          icon: const Icon(Icons.camera_alt),
                          label: const Text('Tomar Foto'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: cardBg,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: Colors.grey.shade700),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _pickImage(ImageSource.gallery),
                          icon: const Icon(Icons.photo_library),
                          label: const Text('Elegir de Galería'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: cardBg,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: Colors.grey.shade700),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Botón Principal: Probar Prenda con IA
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: LinearGradient(
                        colors: _userImageBytes != null
                            ? [const Color(0xFF6C5CE7), const Color(0xFF00CEC9)]
                            : [Colors.grey.shade800, Colors.grey.shade700],
                      ),
                      boxShadow: _userImageBytes != null
                          ? [
                              BoxShadow(
                                color: primaryColor.withValues(alpha: 0.4),
                                blurRadius: 16,
                                offset: const Offset(0, 4),
                              ),
                            ]
                          : [],
                    ),
                    child: ElevatedButton.icon(
                      onPressed: _userImageBytes != null ? _generateTryOn : null,
                      icon: const Icon(Icons.auto_awesome, color: Colors.white),
                      label: const Text(
                        'PROBAR PRENDA',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          letterSpacing: 0.5,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        disabledBackgroundColor: Colors.transparent,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 30),
                ],
              ),
            ),
    );
  }
}
