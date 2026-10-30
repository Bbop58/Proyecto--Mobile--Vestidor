import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../config/api_config.dart';
import 'api_service.dart';

class ChatMessageModel {
  final String role; // 'user' | 'model'
  final String content;
  final DateTime timestamp;

  ChatMessageModel({
    required this.role,
    required this.content,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'role': role,
        'content': content,
      };
}

class ChatbotResponseModel {
  final String reply;
  final List<String> suggestedPrompts;
  final String tenantName;
  final String tenantSlug;

  ChatbotResponseModel({
    required this.reply,
    required this.suggestedPrompts,
    required this.tenantName,
    required this.tenantSlug,
  });

  factory ChatbotResponseModel.fromJson(Map<String, dynamic> json) {
    return ChatbotResponseModel(
      reply: json['reply']?.toString() ?? '',
      suggestedPrompts: (json['suggested_prompts'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      tenantName: json['tenant_name']?.toString() ?? 'FICCT Store',
      tenantSlug: json['tenant_slug']?.toString() ?? 'urbanstyle',
    );
  }
}

class ChatbotService extends ChangeNotifier {
  final ApiService _apiService;

  ChatbotService(this._apiService) {
    _messages.add(
      ChatMessageModel(
        role: 'model',
        content:
            '¡Hola! Soy tu Asistente Virtual Inteligente con IA. ¿En qué puedo asesorarte hoy sobre nuestras prendas, tallas, sucursales o compras?',
      ),
    );
  }

  final List<ChatMessageModel> _messages = [];
  List<ChatMessageModel> get messages => List.unmodifiable(_messages);

  List<String> _suggestedPrompts = [
    '¿Qué prendas tienen en tendencia?',
    '¿Cómo funciona el cambio de talla?',
    '¿Cuáles son las sucursales activas?',
    '¿Qué métodos de pago aceptan?',
  ];
  List<String> get suggestedPrompts => List.unmodifiable(_suggestedPrompts);

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String _tenantName = 'FICCT Store';
  String get tenantName => _tenantName;

  Future<void> sendMessage(String text, {String? tenantSlug}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _isLoading) return;

    final userMsg = ChatMessageModel(role: 'user', content: trimmed);
    _messages.add(userMsg);
    _isLoading = true;
    notifyListeners();

    try {
      final historyList = _messages
          .where((m) => m != userMsg)
          .map((m) => m.toJson())
          .toList();

      final payload = {
        'message': trimmed,
        'history': historyList.length > 6
            ? historyList.sublist(historyList.length - 6)
            : historyList,
        if (tenantSlug != null) 'tenant_slug': tenantSlug,
      };

      final response = await _apiService.postAuth(
        ApiConfig.chatbotMessageUrl,
        payload,
      );

      if (response.success && response.data != null) {
        final data = response.data is Map<String, dynamic>
            ? response.data as Map<String, dynamic>
            : jsonDecode(response.data.toString()) as Map<String, dynamic>;

        final botRes = ChatbotResponseModel.fromJson(data);
        _messages.add(
          ChatMessageModel(role: 'model', content: botRes.reply),
        );
        if (botRes.suggestedPrompts.isNotEmpty) {
          _suggestedPrompts = botRes.suggestedPrompts;
        }
        _tenantName = botRes.tenantName;
      } else {
        _messages.add(
          ChatMessageModel(
            role: 'model',
            content:
                'Disculpa, ocurrió un inconveniente temporal al conectar con la IA. Puedes verificar nuestras sucursales y catálogo en el menú.',
          ),
        );
      }
    } catch (e) {
      _messages.add(
        ChatMessageModel(
          role: 'model',
          content:
              'No pudimos conectar con el servidor. Revisa tu conexión a internet.',
        ),
      );
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void clearHistory() {
    _messages.clear();
    _messages.add(
      ChatMessageModel(
        role: 'model',
        content:
            '¡Hola de nuevo! ¿En qué otra prenda o duda de compra puedo ayudarte?',
      ),
    );
    notifyListeners();
  }
}

