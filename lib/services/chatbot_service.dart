import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../config/api_config.dart';
import '../core/database/database_helper.dart';
import 'api_service.dart';
import 'storage_service.dart';

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

  bool _isCancelled = false;

  bool _isOfflineMode = false;
  bool get isOfflineMode => _isOfflineMode;

  String _tenantName = 'FICCT Store';
  String get tenantName => _tenantName;

  void cancelPendingRequest() {
    if (!_isLoading) return;
    _isCancelled = true;
    _isLoading = false;
    _messages.add(
      ChatMessageModel(
        role: 'model',
        content: '🛑 *Consulta cancelada.* ¿En qué otra consulta puedo orientarte?',
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

      if (_isCancelled) return;

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
        _isOfflineMode = false;
        if (onReply != null) {
          onReply(botRes.reply);
        }
      } else {
        if (!_isCancelled) {
          // Conmutación transparente al motor heurístico offline
          await _handleOfflineFallback(trimmed, tenantSlug, onReply: onReply);
        }
      }
    } catch (e) {
      if (!_isCancelled) {
        // Conmutación transparente al motor heurístico offline ante corte de red o timeout
        await _handleOfflineFallback(trimmed, tenantSlug, onReply: onReply);
      }
    } finally {
      if (!_isCancelled) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Motor Heurístico Offline Ultraligero (< 5ms)
  /// Responde de forma precisa ante cortes de señal sin modelos pesados ni sobrecargar el teléfono
  Future<void> _handleOfflineFallback(
    String rawText,
    String? tenantSlug, {
    Function(String reply)? onReply,
  }) async {
    _isOfflineMode = true;
    final msg = rawText.toLowerCase();

    String reply;

    if (msg.contains('saldo') ||
        msg.contains('billetera') ||
        msg.contains('plata') ||
        msg.contains('wallet') ||
        msg.contains('cuanto tengo')) {
      double saldoLocal = 0.0;
      try {
        final storage = StorageService();
        final userId = await storage.getUserId();
        if (userId != null && userId.isNotEmpty) {
          final wallet = await DatabaseHelper.instance.getLocalWallet(userId);
          if (wallet != null) {
            saldoLocal = (wallet['saldo'] as num?)?.toDouble() ?? 0.0;
          }
        }
      } catch (e) {
        debugPrint('Error leyendo billetera local offline: $e');
      }

      reply =
          '💳 **Saldo en Billetera Offline (SQLite Local)**\n\n'
          'Dispones de **${saldoLocal.toStringAsFixed(2)} Bs.** almacenados de forma segura con sellado criptográfico HMAC-SHA256 en este dispositivo.\n\n'
          'Puedes usar este saldo para pagar en el carrito en modo avión sin necesidad de señal.';
    } else if (msg.contains('mis compras') ||
        msg.contains('que compre') ||
        msg.contains('mis pedidos') ||
        msg.contains('recibo') ||
        msg.contains('historial')) {
      int pending = 0;
      try {
        final orders = await DatabaseHelper.instance.getPendingOfflineWalletOrders();
        pending = orders.length;
      } catch (_) {}

      reply =
          '🛍️ **Mis Compras en Modo Offline**\n\n'
          'Actualmente tienes **$pending compra(s) offline** registradas localmente en cola de sincronización segura (Store-and-Forward).\n\n'
          'Tan pronto tu teléfono recupere la conexión a internet, se enviarán automáticamente a la tienda central y recibirás una notificación con tus números de recibo oficiales.';
    } else if (msg.contains('como comprar') ||
        msg.contains('compras offline') ||
        msg.contains('sin internet') ||
        msg.contains('modo avion')) {
      reply =
          '✈️ **¿Cómo comprar con Billetera sin Internet?**\n\n'
          '1. Añade tus prendas favoritas al carrito.\n'
          '2. Al pagar, selecciona **"Pagar con Billetera (Offline / Online)"**.\n'
          '3. Tu balance local se descuenta de inmediato y se genera un comprobante criptográfico seguro.\n'
          '4. ¡Listo! Al volver a conectarte a internet, el sistema sincroniza automáticamente con el Kardex central.';
    } else if (msg.contains('talla') ||
        msg.contains('medida') ||
        msg.contains('como se mi talla') ||
        msg.contains('guia de tallas')) {
      reply =
          '📏 **Guía Métrica de Tallas (Moda Urbana & Formal)**\n\n'
          'Para encontrar tu talla ideal, mide tu contorno con una cinta métrica:\n'
          '• **Talla S:** Pecho 88-94 cm | Cintura 74-80 cm\n'
          '• **Talla M:** Pecho 96-102 cm | Cintura 82-88 cm\n'
          '• **Talla L:** Pecho 104-110 cm | Cintura 90-96 cm\n'
          '• **Talla XL:** Pecho 112-118 cm | Cintura 98-104 cm\n\n'
          '💡 *Tip:* Si eliges prendas con corte *Oversize*, tu talla habitual te brindará la caída holgada perfecta.';
    } else if (msg.contains('cuidado') ||
        msg.contains('lavar') ||
        msg.contains('planchar') ||
        msg.contains('tela')) {
      reply =
          '🧼 **Guía de Cuidado de Prendas y Telas**\n\n'
          '• **Algodón Peinado / Poleras:** Lavar con agua fría (< 30°C) para evitar encogimiento. Secar a la sombra.\n'
          '• **Chaquetas y Pantalones Denim:** Lavar siempre del revés para preservar el tinte índigo original.\n'
          '• **Prendas con Estampados:** Planchar siempre por el reverso a temperatura media.';
    } else if (msg.contains('recomiend') ||
        msg.contains('gust') ||
        msg.contains('para mi') ||
        msg.contains('suger') ||
        msg.contains('que comprar') ||
        msg.contains('tendencia') ||
        msg.contains('moda')) {
      reply =
          '✨ **Recomendación Personalizada (Modo Sin Conexión)**\n\n'
          'Según el catálogo de nuestra tienda y tendencias vigentes:\n'
          '• **Línea Formal / Ejecutiva:** Ternos Slim Fit y Vestidos de Gala de alta confección.\n'
          '• **Línea Casual / Urbana:** Hoodies con diseño gráfico y Poleras Streetwear de algodón peinado.\n\n'
          '💡 *Tip:* Recuerda que puedes tocar el ícono de **Corazón (❤️)** en cualquier prenda para guardarla en tus **Favoritos** y revisarla en cualquier momento, incluso sin internet.';
    } else if (msg.contains('favorit') ||
        msg.contains('deseo') ||
        msg.contains('wishlist') ||
        msg.contains('guardad')) {
      reply =
          '❤️ **Tus Prendas Favoritas**\n\n'
          'Puedes consultar todas tus prendas guardadas desde la sección de **Favoritos** en la barra superior o desde tu perfil.\n'
          'Tus favoritos se mantienen sincronizados en la base de datos local de tu teléfono para que no pierdas de vista las prendas que más te gustan.';
    } else if (msg.contains('sucursal') ||
        msg.contains('tienda') ||
        msg.contains('donde') ||
        msg.contains('ubicacion') ||
        msg.contains('direccion') ||
        msg.contains('horario') ||
        msg.contains('tarija') ||
        msg.contains('santa cruz')) {
      reply =
          '📍 **Sucursales y Horarios de Atención**\n\n'
          'Nuestras tiendas físicas atienden de **Lunes a Sábado de 09:00 a 20:00**:\n'
          '• **Sucursal Tarija:** Calle Sucre #450 (Centro Histórico).\n'
          '• **Sucursal Santa Cruz:** Av. San Martín #100 (Equipetrol) y Sucursal Centro Comercial.\n\n'
          '¡Puedes apartar prendas desde la App y pasar a retirarlas en la sucursal más cercana!';
    } else if (msg.contains('cambio') ||
        msg.contains('devoluc') ||
        msg.contains('devolver') ||
        msg.contains('talla') ||
        msg.contains('garantia') ||
        msg.contains('30 dias') ||
        msg.contains('reembolso')) {
      reply =
          '🔄 **Garantía Retail y Política de Cambios (30 Días)**\n\n'
          '• **Plazo:** Hasta 30 días posteriores a tu compra presentando tu Nota de Venta digital o física.\n'
          '• **Cambio de Talla:** Sin ningún costo adicional si la prenda tiene el mismo precio de lista.\n'
          '• **Prenda de Mayor Valor:** Solo abonas la diferencia en caja (Efectivo o PayPal).\n'
          '• **Prenda de Menor Valor:** La diferencia a tu favor se deposita automáticamente como saldo en tu Billetera Virtual.\n\n'
          '*(Condición: La prenda debe encontrarse limpia y con etiquetas originales)*.';
    } else if (msg.contains('pago') ||
        msg.contains('pagar') ||
        msg.contains('efectivo') ||
        msg.contains('paypal') ||
        msg.contains('billetera') ||
        msg.contains('saldo') ||
        msg.contains('fondos') ||
        msg.contains('tarjeta') ||
        msg.contains('qr')) {
      reply =
          '💳 **Métodos de Pago Autorizados**\n\n'
          'Nuestros métodos oficiales autorizados son:\n'
          '1. **Efectivo:** En mostrador de cualquier sucursal con cálculo automático de vuelto.\n'
          '2. **PayPal Checkout:** En dólares estadounidenses (tipo de cambio 6.96 Bs/USD) para compras digitales desde la App Móvil.\n\n'
          '*(Por políticas de seguridad, no operamos con códigos QR ni transferencias directas)*.';
    } else if (msg.contains('reserva') ||
        msg.contains('apartar') ||
        msg.contains('recojo') ||
        msg.contains('click and collect')) {
      reply =
          '🛍️ **Servicio Click & Collect (Apartados)**\n\n'
          '1. Elige tu prenda y talla en la App Móvil y selecciona *"Apartar para Recojo"*.\n'
          '2. El encargado de tienda aparta la prenda de inmediato.\n'
          '3. Tienes hasta **48 horas** de vigencia para pasar por la sucursal y abonarla en Efectivo al recogerla.';
    } else if (msg.contains('envio') ||
        msg.contains('delivery') ||
        msg.contains('domicilio') ||
        msg.contains('costo envio') ||
        msg.contains('moto') ||
        msg.contains('cuanto tarda')) {
      reply =
          '🛵 **Envíos y Delivery a Domicilio**\n\n'
          '• **Tarija (Radio Urbano):** 10.00 Bs. (Entrega en 2 a 4 hrs).\n'
          '• **Santa Cruz (1er a 4to Anillo):** 15.00 Bs. / Equipetrol y Norte: 20.00 Bs.\n\n'
          'Recibirás notificaciones en la barra de tu teléfono cuando el repartidor esté en camino.';
    } else {
      reply =
          '⚡ **Asistente Local (Modo Sin Conexión)**\n\n'
          'Actualmente no dispones de conexión a internet, pero sigo activo con la base de datos local guardada en tu teléfono.\n\n'
          'Puedo ayudarte con:\n'
          '• ✨ Recomendaciones de prendas según tus gustos\n'
          '• 📍 Sucursales y horarios de atención\n'
          '• 🔄 Políticas de cambio de prendas (30 días)\n'
          '• 💳 Métodos de pago y servicio de recogida\n\n'
          '¡Toca cualquiera de las sugerencias rápidas abajo para continuar!';
    }

    _messages.add(ChatMessageModel(role: 'model', content: reply));
    if (onReply != null) {
      onReply(reply);
    }

    _suggestedPrompts = [
      '✨ ¿Qué me recomiendas según mis gustos?',
      '📍 Ver Sucursales y Horarios',
      '🔄 Política de Cambios (30 días)',
      '💳 Métodos de Pago Aceptados',
    ];
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

