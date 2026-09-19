import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

import '../models/product.dart';
import '../models/product_variant.dart';
import 'virtual_tryon_screen.dart';

class ARMirrorScreen extends StatefulWidget {
  final Product product;
  final ProductVariant initialVariant;

  const ARMirrorScreen({
    super.key,
    required this.product,
    required this.initialVariant,
  });

  @override
  State<ARMirrorScreen> createState() => _ARMirrorScreenState();
}

class _ARMirrorScreenState extends State<ARMirrorScreen> {
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  int _selectedCameraIndex = 1; // Default to front camera if available
  bool _isCameraInitialized = false;
  bool _cameraError = false;

  late ProductVariant _currentVariant;
  double _garmentScale = 1.0;
  Offset _garmentPosition = const Offset(0, 40);
  double _garmentOpacity = 0.92;
  bool _showTorsoGuide = true;
  bool _isCapturing = false;

  @override
  void initState() {
    super.initState();
    _currentVariant = widget.initialVariant;
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras != null && _cameras!.isNotEmpty) {
        // Try to find front camera
        final frontIndex = _cameras!.indexWhere(
          (c) => c.lensDirection == CameraLensDirection.front,
        );
        _selectedCameraIndex = frontIndex != -1 ? frontIndex : 0;

        await _startCamera(_cameras![_selectedCameraIndex]);
      } else {
        setState(() => _cameraError = true);
      }
    } catch (e) {
      debugPrint('[ARMirrorScreen] Error inicializando cámara: $e');
      setState(() => _cameraError = true);
    }
  }

  Future<void> _startCamera(CameraDescription cameraDescription) async {
    if (_cameraController != null) {
      await _cameraController!.dispose();
    }

    _cameraController = CameraController(
      cameraDescription,
      ResolutionPreset.high,
      enableAudio: false,
    );

    try {
      await _cameraController!.initialize();
      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
          _cameraError = false;
        });
      }
    } catch (e) {
      debugPrint('[ARMirrorScreen] Error al iniciar controller: $e');
      if (mounted) {
        setState(() => _cameraError = true);
      }
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras == null || _cameras!.length < 2) return;
    setState(() => _isCameraInitialized = false);
    _selectedCameraIndex = (_selectedCameraIndex + 1) % _cameras!.length;
    await _startCamera(_cameras![_selectedCameraIndex]);
  }

  Future<void> _captureSnapshot() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;

    setState(() => _isCapturing = true);

    try {
      final XFile photo = await _cameraController!.takePicture();
      final bytes = await photo.readAsBytes();

      if (mounted) {
        setState(() => _isCapturing = false);
        // Navigate to Virtual Try-On Screen with the captured frame
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => VirtualTryOnScreen(
              product: widget.product,
              initialVariant: _currentVariant,
              preloadedImageBytes: bytes,
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('[ARMirrorScreen] Error capturando snapshot: $e');
      if (mounted) {
        setState(() => _isCapturing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al capturar: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF6C5CE7);
    const neonCyan = Color(0xFF00CEC9);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Live Camera Feed or Studio Fallback
          if (_isCameraInitialized && _cameraController != null)
            Center(
              child: CameraPreview(_cameraController!),
            )
          else if (_cameraError)
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF0F111A), Color(0xFF1B1E2E)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.videocam_off, size: 70, color: Colors.white54),
                    const SizedBox(height: 16),
                    const Text(
                      'No se pudo acceder a la cámara en vivo.',
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Revisa los permisos de cámara en tu dispositivo.',
                      style: TextStyle(color: Colors.white60, fontSize: 13),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: _initializeCamera,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Reintentar Cámara'),
                      style: ElevatedButton.styleFrom(backgroundColor: primaryColor),
                    ),
                  ],
                ),
              ),
            )
          else
            const Center(
              child: CircularProgressIndicator(color: neonCyan),
            ),

          // 2. Torso Guide Overlay (Optional)
          if (_showTorsoGuide)
            Center(
              child: IgnorePointer(
                child: Container(
                  width: 280,
                  height: 380,
                  decoration: BoxDecoration(
                    border: Border.all(color: neonCyan.withOpacity(0.35), width: 1.5),
                    borderRadius: BorderRadius.circular(140),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.accessibility_new, size: 120, color: Colors.white.withOpacity(0.15)),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'Ubica tus hombros dentro del marco',
                          style: TextStyle(color: neonCyan, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // 3. Interactive AR Superimposed Garment Layer
          Center(
            child: Transform.translate(
              offset: _garmentPosition,
              child: Transform.scale(
                scale: _garmentScale,
                child: GestureDetector(
                  onPanUpdate: (details) {
                    setState(() {
                      _garmentPosition += details.delta;
                    });
                  },
                  child: Opacity(
                    opacity: _garmentOpacity,
                    child: Container(
                      width: 280,
                      height: 320,
                      decoration: BoxDecoration(
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.35),
                            blurRadius: 18,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                      child: Image.network(
                        widget.product.imagenUrl ?? '',
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.checkroom,
                          size: 140,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // 4. AR Tracking HUD Markers (Corners)
          Positioned(
            top: 50,
            left: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.65),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: neonCyan),
              ),
              child: const Row(
                children: [
                  Icon(Icons.circle, color: Color(0xFF00B894), size: 10),
                  SizedBox(width: 6),
                  Text(
                    'ESPEJO AR EN VIVO • 60 FPS',
                    style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),

          // Top Action Buttons (Close, Switch Camera, Toggle Guide)
          Positioned(
            top: 46,
            right: 16,
            child: Row(
              children: [
                IconButton(
                  onPressed: () => setState(() => _showTorsoGuide = !_showTorsoGuide),
                  icon: Icon(
                    _showTorsoGuide ? Icons.grid_on : Icons.grid_off,
                    color: _showTorsoGuide ? neonCyan : Colors.white70,
                  ),
                  tooltip: 'Guía de postura',
                ),
                IconButton(
                  onPressed: _switchCamera,
                  icon: const Icon(Icons.flip_camera_ios, color: Colors.white),
                  tooltip: 'Cambiar cámara',
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.white, size: 28),
                ),
              ],
            ),
          ),

          // 5. Controls Overlay (Scale, Opacity, Variants, Capture)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.transparent, Colors.black.withOpacity(0.85), Colors.black],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Sliders: Escala y Ajuste
                  Row(
                    children: [
                      const Icon(Icons.zoom_in, color: Colors.white70, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: neonCyan,
                            thumbColor: Colors.white,
                            trackHeight: 3,
                          ),
                          child: Slider(
                            value: _garmentScale,
                            min: 0.6,
                            max: 1.6,
                            onChanged: (val) => setState(() => _garmentScale = val),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => setState(() {
                          _garmentPosition = const Offset(0, 40);
                          _garmentScale = 1.0;
                        }),
                        icon: const Icon(Icons.center_focus_strong, color: Colors.white70, size: 20),
                        tooltip: 'Centrar prenda',
                      ),
                    ],
                  ),

                  // Selector de Color en Vivo
                  if (widget.product.variantes.isNotEmpty) ...[
                    SizedBox(
                      height: 38,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: widget.product.variantes.length,
                        itemBuilder: (context, index) {
                          final v = widget.product.variantes[index];
                          final isSelected = v.id == _currentVariant.id;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text('${v.color} (${v.talla})'),
                              selected: isSelected,
                              selectedColor: primaryColor,
                              backgroundColor: const Color(0xFF1B1E2E),
                              labelStyle: TextStyle(
                                color: isSelected ? Colors.white : Colors.grey.shade300,
                                fontSize: 11,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              ),
                              onSelected: (selected) {
                                if (selected) {
                                  setState(() => _currentVariant = v);
                                }
                              },
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Capture Button
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Botón Reset
                      TextButton.icon(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back, color: Colors.white70, size: 18),
                        label: const Text('Volver', style: TextStyle(color: Colors.white70)),
                      ),

                      // Botón Disparador Snapshot AR
                      GestureDetector(
                        onTap: _isCapturing ? null : _captureSnapshot,
                        child: Container(
                          width: 68,
                          height: 68,
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: neonCyan, width: 3),
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                colors: [Color(0xFF6C5CE7), Color(0xFF00CEC9)],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: neonCyan.withOpacity(0.5),
                                  blurRadius: 12,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: _isCapturing
                                ? const Padding(
                                    padding: EdgeInsets.all(18),
                                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                  )
                                : const Icon(Icons.camera_alt, color: Colors.white, size: 30),
                          ),
                        ),
                      ),

                      // Botón Info / Ayuda
                      TextButton.icon(
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              backgroundColor: const Color(0xFF1B1E2E),
                              title: const Row(
                                children: [
                                  Icon(Icons.tips_and_updates, color: Color(0xFFFFEAA7)),
                                  SizedBox(width: 8),
                                  Text('Cómo usar el Espejo AR', style: TextStyle(color: Colors.white, fontSize: 16)),
                                ],
                              ),
                              content: const Text(
                                '1. Coloca tu teléfono frente a ti.\n'
                                '2. Arrastra la prenda con el dedo para alinearla a tus hombros.\n'
                                '3. Ajusta el zoom con la barra deslizante.\n'
                                '4. Cambia los colores abajo en tiempo real.\n'
                                '5. Pulsa el botón circular para capturar y analizar tu calce con la IA.',
                                style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  child: const Text('¡Entendido!', style: TextStyle(color: neonCyan)),
                                ),
                              ],
                            ),
                          );
                        },
                        icon: const Icon(Icons.help_outline, color: Colors.white70, size: 18),
                        label: const Text('Ayuda', style: TextStyle(color: Colors.white70)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
