import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

class TtsService extends ChangeNotifier {
  final FlutterTts _flutterTts = FlutterTts();

  bool _isSpeaking = false;
  bool get isSpeaking => _isSpeaking;

  String? _currentSpeakingId;
  String? get currentSpeakingId => _currentSpeakingId;

  bool _autoSpeakEnabled = false;
  bool get autoSpeakEnabled => _autoSpeakEnabled;

  TtsService() {
    _initTts();
  }

  Future<void> _initTts() async {
    try {
      await _flutterTts.setLanguage('es-US');
      await _flutterTts.setSpeechRate(0.5); // Velocidad natural y clara
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);

      _flutterTts.setStartHandler(() {
        _isSpeaking = true;
        notifyListeners();
      });

      _flutterTts.setCompletionHandler(() {
        _isSpeaking = false;
        _currentSpeakingId = null;
        notifyListeners();
      });

      _flutterTts.setCancelHandler(() {
        _isSpeaking = false;
        _currentSpeakingId = null;
        notifyListeners();
      });

      _flutterTts.setErrorHandler((msg) {
        _isSpeaking = false;
        _currentSpeakingId = null;
        notifyListeners();
      });
    } catch (e) {
      debugPrint('Error inicializando FlutterTts: $e');
    }
  }

  void toggleAutoSpeak() {
    _autoSpeakEnabled = !_autoSpeakEnabled;
    if (!_autoSpeakEnabled && _isSpeaking) {
      stop();
    }
    notifyListeners();
  }

  /// Limpia la sintaxis Markdown antes de sintetizar voz, para evitar que la
  /// narración pronuncie asteriscos, viñetas, numerales o enlaces técnicos.
  String sanitizeMarkdown(String text) {
    if (text.isEmpty) return '';
    return text
        // Eliminar bloques de código y código inline
        .replaceAll(RegExp(r'```[\s\S]*?```'), 'código omitido.')
        .replaceAll(RegExp(r'`([^`]+)`'), r'$1')
        // Eliminar formato negrita, cursiva y tachado
        .replaceAll(RegExp(r'(\*\*|__)(.*?)\1'), r'$2')
        .replaceAll(RegExp(r'(\*|_)(.*?)\1'), r'$2')
        .replaceAll(RegExp(r'~~(.*?)~~'), r'$1')
        // Eliminar encabezados (###)
        .replaceAll(RegExp(r'#{1,6}\s+'), '')
        // Eliminar enlaces [texto](url) -> texto
        .replaceAll(RegExp(r'\[([^\]]+)\]\([^\)]+\)'), r'$1')
        // Eliminar viñetas y numerales de lista
        .replaceAll(RegExp(r'^\s*[\*\-\+•]\s+', multiLine: true), '')
        .replaceAll(RegExp(r'^\s*\d+\.\s+', multiLine: true), '')
        // Eliminar separadores horizontales
        .replaceAll(RegExp(r'---+'), '')
        // Normalizar espacios múltiples y saltos de línea
        .replaceAll(RegExp(r'\n+'), '. ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Future<void> speak(String text, {String? id}) async {
    final cleanText = sanitizeMarkdown(text);
    if (cleanText.isEmpty) return;

    await stop();
    _currentSpeakingId = id;
    _isSpeaking = true;
    notifyListeners();

    try {
      await _flutterTts.speak(cleanText);
    } catch (e) {
      debugPrint('Error en speak: $e');
      _isSpeaking = false;
      _currentSpeakingId = null;
      notifyListeners();
    }
  }

  Future<void> toggleSpeak(String text, {String? id}) async {
    if (_isSpeaking && (id != null && _currentSpeakingId == id)) {
      await stop();
    } else {
      await speak(text, id: id);
    }
  }

  Future<void> stop() async {
    try {
      await _flutterTts.stop();
    } catch (e) {
      debugPrint('Error al detener TTS: $e');
    }
    _isSpeaking = false;
    _currentSpeakingId = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _flutterTts.stop();
    super.dispose();
  }
}
