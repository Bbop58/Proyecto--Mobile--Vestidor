import 'package:flutter/foundation.dart';

// Conditionally import dart:html on web
import 'dart:html' as html if (dart.library.io) 'package:flutter/foundation.dart';

class UrlHelper {
  static void openUrl(String url) {
    if (kIsWeb) {
      try {
        html.window.open(url, '_blank');
      } catch (e) {
        debugPrint('Error abriendo URL: $e');
      }
    }
  }
}
