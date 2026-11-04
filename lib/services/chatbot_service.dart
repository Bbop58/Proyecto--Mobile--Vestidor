import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../config/api_config.dart';
import '../core/database/database_helper.dart';
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

  Map<String, dynamic> toJson() => {'role': role, 'content': content};
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
      suggestedPrompts:
          (json['suggested_prompts'] as List<dynamic>?)
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
  int _generation = 0;
  bool _disposed = false;
  void _resetScope() {
    _generation++;
    _isLoading = false;
    _isOfflineMode = false;
    _tenantName = 'FICCT Store';
    _suggestedPrompts = [];
    clearHistory();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    DatabaseHelper.scopeChanges.removeListener(_resetScope);
    super.dispose();
  }

  ChatbotService(this._apiService) {
    DatabaseHelper.scopeChanges.addListener(_resetScope);
    _messages.add(
      ChatMessageModel(
        role: 'model',
        content: '¡Hola! Soy tu Asistente Virtual Inteligente con IA. ¿En qué puedo asesorarte hoy sobre nuestras prendas, tallas, sucursales o compras?',
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

  bool _isCancelled = false;

  bool _isOfflineMode = false;
  bool get isOfflineMode => _isOfflineMode;

  String _tenantName = 'FICCT Store';
  String get tenantName => _tenantName;

  void cancelPendingRequest() {
    if (!_isLoading) return;
    _generation++;
    _isCancelled = true;
    _isLoading = false;
    _messages.add(
      ChatMessageModel(
        role: 'model',
        content:
            '🛑 *Consulta cancelada.* ¿En qué otra consulta puedo orientarte?',
      ),
    );
    notifyListeners();
  }

  Future<void> sendMessage(
    String text, {
    String? tenantSlug,
    Function(String reply)? onReply,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _isLoading) return;

    final generation = ++_generation;
    _isCancelled = false;
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

      if (_disposed || generation != _generation || _isCancelled) return;

      if (response.success && response.data != null) {
        final data = response.data is Map<String, dynamic>
            ? response.data as Map<String, dynamic>
            : jsonDecode(response.data.toString()) as Map<String, dynamic>;

        final botRes = ChatbotResponseModel.fromJson(data);
        _messages.add(ChatMessageModel(role: 'model', content: botRes.reply));
        if (botRes.suggestedPrompts.isNotEmpty) {
          _suggestedPrompts = botRes.suggestedPrompts;
        }
        _tenantName = botRes.tenantName;
        _isOfflineMode = false;
        if (onReply != null) {
          onReply(botRes.reply);
        }
      } else {
        if (!_disposed && generation == _generation && !_isCancelled) {
          // Conmutación transparente al motor heurístico offline
          await _handleOfflineFallback(trimmed, tenantSlug, onReply: onReply);
        }
      }
    } catch (e) {
      if (!_disposed && generation == _generation && !_isCancelled) {
        // Conmutación transparente al motor heurístico offline ante corte de red o timeout
        await _handleOfflineFallback(trimmed, tenantSlug, onReply: onReply);
      }
    } finally {
      if (!_disposed && generation == _generation && !_isCancelled) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> _handleOfflineFallback(
    String rawText,
    String? tenantSlug, {
    Function(String reply)? onReply,
  }) async {
    _isOfflineMode = true;
    const reply =
        'No pude consultar el asistente. Revisa tu conexión e intenta nuevamente. No se confirmaron saldos, precios, existencias ni tarifas de envío.';
    _messages.add(ChatMessageModel(role: 'model', content: reply));
    onReply?.call(reply);
  }

  void clearHistory() {
    _generation++;
    _messages.clear();
    _messages.add(
      ChatMessageModel(
        role: 'model',
        content: '¡Hola de nuevo! ¿En qué otra prenda o duda de compra puedo ayudarte?',
      ),
    );
    notifyListeners();
  }
}
