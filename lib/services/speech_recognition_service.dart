import 'package:speech_to_text/speech_to_text.dart';

class SpeechRecognitionService {
  final SpeechToText _speech = SpeechToText();
  bool get isListening => _speech.isListening;

  Future<bool> initialize({void Function(bool)? onListening}) => _speech.initialize(
    onStatus: (status) => onListening?.call(status == 'listening'),
  );

  Future<void> listen(void Function(String) onText, {void Function(bool)? onListening}) async {
    if (!await initialize(onListening: onListening)) {
      throw const FormatException(
        'Reconocimiento de voz no disponible. Puedes escribir tu pregunta.',
      );
    }
    final locales = await _speech.locales();
    final spanish = locales
        .where((x) => x.localeId.toLowerCase().startsWith('es'))
        .toList();
    await _speech.listen(
      onResult: (result) => onText(result.recognizedWords),
      listenOptions: SpeechListenOptions(
        localeId: spanish.isEmpty ? null : spanish.first.localeId,
      ),
    );
  }

  Future<void> stop() => _speech.stop();
  void dispose() {
    _speech.cancel();
  }
}
