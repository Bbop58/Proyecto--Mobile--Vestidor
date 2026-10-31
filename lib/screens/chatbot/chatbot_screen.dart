import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../services/chatbot_service.dart';
import '../../services/tts_service.dart';

class ChatbotScreen extends StatefulWidget {
  const ChatbotScreen({super.key});

  @override
  State<ChatbotScreen> createState() => _ChatbotScreenState();
}

class _ChatbotScreenState extends State<ChatbotScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendMessage(ChatbotService service, TtsService ttsService, String text) {
    if (text.trim().isEmpty) return;
    _textController.clear();
    service.sendMessage(
      text,
      onReply: (reply) {
        if (ttsService.autoSpeakEnabled) {
          ttsService.speak(reply, id: reply);
        }
      },
    );
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final chatbotService = context.watch<ChatbotService>();
    final ttsService = context.watch<TtsService>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = AppTheme.getAccent(context);

    // Auto-scroll on new message
    _scrollToBottom();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Asistente Virtual',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: chatbotService.isOfflineMode
                        ? Colors.amber.withValues(alpha: 0.2)
                        : Colors.green.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: chatbotService.isOfflineMode
                          ? Colors.amber.shade700
                          : Colors.green.shade600,
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: chatbotService.isOfflineMode
                              ? Colors.amber.shade700
                              : Colors.green.shade600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        chatbotService.isOfflineMode ? 'Modo Offline' : 'Gemini IA',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: chatbotService.isOfflineMode
                              ? Colors.amber.shade900
                              : Colors.green.shade800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Text(
              chatbotService.isOfflineMode
                  ? '${chatbotService.tenantName} • Motor Local Heurístico (< 5ms)'
                  : '${chatbotService.tenantName} • Gemini 3.1 Flash-Lite (Nube)',
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              ttsService.autoSpeakEnabled ? Icons.volume_up_rounded : Icons.volume_off_rounded,
              color: ttsService.autoSpeakEnabled ? Colors.greenAccent : null,
            ),
            tooltip: ttsService.autoSpeakEnabled
                ? 'Lectura automática activada (clic para silenciar)'
                : 'Activar lectura automática por voz',
            onPressed: () => ttsService.toggleAutoSpeak(),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Reiniciar conversación',
            onPressed: () {
              ttsService.stop();
              chatbotService.clearHistory();
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Message List
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                itemCount: chatbotService.messages.length + (chatbotService.isLoading ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == chatbotService.messages.length && chatbotService.isLoading) {
                    return _buildTypingIndicator(context, isDark, primaryColor);
                  }

                  final msg = chatbotService.messages[index];
                  final isUser = msg.role == 'user';
                  return _buildMessageBubble(context, msg, isUser, isDark, primaryColor, ttsService);
                },
              ),
            ),

            // Quick Prompts Bar
            if (!chatbotService.isLoading && chatbotService.suggestedPrompts.isNotEmpty)
              Container(
                height: 44,
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: chatbotService.suggestedPrompts.length,
                  separatorBuilder: (context, index) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final prompt = chatbotService.suggestedPrompts[index];
                    return ActionChip(
                      label: Text(
                        prompt,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                        ),
                      ),
                      backgroundColor: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: BorderSide(
                          color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                        ),
                      ),
                      onPressed: () => _sendMessage(chatbotService, ttsService, prompt),
                    );
                  },
                ),
              ),

            // Input Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                border: Border(
                  top: BorderSide(
                    color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (val) => _sendMessage(chatbotService, ttsService, val),
                      decoration: InputDecoration(
                        hintText: 'Pregunta sobre ropa, tallas o tiendas...',
                        hintStyle: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.grey.shade500 : Colors.grey.shade400,
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide(
                            color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide(
                            color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide(color: primaryColor, width: 1.5),
                        ),
                        filled: true,
                        fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    backgroundColor: chatbotService.isLoading ? Colors.red.shade400 : primaryColor,
                    radius: 20,
                    child: IconButton(
                      icon: Icon(
                        chatbotService.isLoading ? Icons.stop_rounded : Icons.send_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                      tooltip: chatbotService.isLoading ? 'Cancelar envío' : 'Enviar consulta',
                      onPressed: chatbotService.isLoading
                          ? () => chatbotService.cancelPendingRequest()
                          : () => _sendMessage(chatbotService, ttsService, _textController.text),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(
    BuildContext context,
    ChatMessageModel msg,
    bool isUser,
    bool isDark,
    Color primaryColor,
    TtsService ttsService,
  ) {
    final isSpeaking = ttsService.isSpeaking && ttsService.currentSpeakingId == msg.content;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 14,
              backgroundColor: isDark ? Colors.grey.shade800 : Colors.indigo.shade50,
              child: Icon(Icons.smart_toy_rounded, size: 16, color: primaryColor),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser
                    ? primaryColor
                    : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: isUser ? const Radius.circular(16) : const Radius.circular(4),
                  bottomRight: isUser ? const Radius.circular(4) : const Radius.circular(16),
                ),
                border: isUser
                    ? null
                    : Border.all(
                        color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
                      ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    msg.content,
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.4,
                      color: isUser
                          ? Colors.white
                          : (isDark ? Colors.grey.shade100 : const Color(0xFF0F172A)),
                    ),
                  ),
                  if (!isUser) ...[
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        InkWell(
                          onTap: () => ttsService.toggleSpeak(msg.content, id: msg.content),
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isSpeaking ? Icons.stop_circle_rounded : Icons.volume_up_rounded,
                                  size: 16,
                                  color: isSpeaking
                                      ? Colors.redAccent
                                      : (isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  isSpeaking ? 'Detener voz' : 'Escuchar',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: isSpeaking
                                        ? Colors.redAccent
                                        : (isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (isUser) const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator(BuildContext context, bool isDark, Color primaryColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: isDark ? Colors.grey.shade800 : Colors.indigo.shade50,
            child: Icon(Icons.smart_toy_rounded, size: 16, color: primaryColor),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: primaryColor),
                ),
                const SizedBox(width: 8),
                Text(
                  'El asistente está pensando...',
                  style: TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

