import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/services/tts_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('voice preserves text values while removing markdown delimiters', () {
    final tts = TtsService();
    expect(
      tts.sanitizeMarkdown(
        '**Saldo 37 Bs.** [Ver tienda](https://example.com) `SKU`',
      ),
      'Saldo 37 Bs. Ver tienda SKU',
    );
    // No playback is requested; only deterministic text preparation.
  });
}
