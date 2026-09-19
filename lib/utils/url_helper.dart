import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

class UrlHelper {
  /// Abre una URL en el navegador del dispositivo (externo) o en la web.
  /// Usar LaunchMode.externalApplication es vital en Android/iOS para que la
  /// pasarela de PayPal Sandbox cargue formularios, cookies y scripts de login
  /// sin restricciones de seguridad de webviews internos.
  static Future<bool> openUrl(String url) async {
    try {
      final uri = Uri.tryParse(url.trim());
      if (uri == null) {
        debugPrint('UrlHelper: URL inválida -> $url');
        return false;
      }

      if (!kIsWeb) {
        final launched = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        if (launched) return true;
      }

      // Fallback a modo por defecto de la plataforma
      return await launchUrl(
        uri,
        mode: LaunchMode.platformDefault,
      );
    } catch (e) {
      debugPrint('UrlHelper: Error al abrir URL ($url): $e');
      return false;
    }
  }
}
