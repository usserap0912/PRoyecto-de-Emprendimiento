import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:safezone/theme/app_theme.dart';
import 'package:safezone/models/chat_message.dart';
import 'package:safezone/services/chat_service.dart';
import 'package:safezone/services/sound_service.dart';
import 'package:timeago/timeago.dart' as timeago;

class CommunityChatScreen extends StatefulWidget {
  final String userCode;

  const CommunityChatScreen({super.key, required this.userCode});

  @override
  State<CommunityChatScreen> createState() => _CommunityChatScreenState();
}

class _CommunityChatScreenState extends State<CommunityChatScreen> {
  final ChatService _chatService = ChatService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<ChatMessage> _messages = [];
  bool _isLoading = true;
  StreamSubscription<List<ChatMessage>>? _messageSubscription;
  bool _someoneIsTyping = false;

  // Para detectar mensajes nuevos y reproducir sonido
  int _previousMessageCount = 0;
  bool _initialLoadDone = false;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _loadMessagesAndSubscribe();
  }

  Future<void> _loadMessagesAndSubscribe() async {
    // Primero cargar mensajes existentes
    await _loadMessages();

    // Luego suscribirse al stream en tiempo real
    _messageSubscription = _chatService.getMessagesStream().listen((messages) {
      if (mounted) {
        setState(() {
          // Detectar si hay mensajes nuevos (de otros usuarios)
          if (_initialLoadDone &&
              messages.isNotEmpty &&
              _previousMessageCount > 0 &&
              messages.length > _previousMessageCount &&
              messages.first.userCode != widget.userCode) {
            SoundService().play('nav_tap');
            HapticFeedback.lightImpact();
          }

          _previousMessageCount = messages.length;
          _messages = messages;
          _isLoading = false;
        });
        _scrollToBottom();
      }
    });
  }

  Future<void> _loadMessages() async {
    try {
      final messages = await _chatService.getMessages();
      if (mounted) {
        setState(() {
          _messages = messages;
          _isLoading = false;
          _previousMessageCount = messages.length;
          _initialLoadDone = true;
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _initialLoadDone = true;
      }
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty) return;

    if (_isSending) return;
    setState(() => _isSending = true);
    try {
      final inserted = await _chatService.sendMessage(widget.userCode, content);
      if (!mounted) return;
      setState(() {
        if (!_messages.any((message) => message.id == inserted.id)) {
          _messages = [..._messages, inserted]
            ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
        }
      });
      _messageController.clear();
      SoundService().play('nav_tap');
      HapticFeedback.selectionClick();
      _scrollToBottom();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No pudimos enviar el mensaje. Intenta nuevamente.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Detecta si hay actividad reciente de otros usuarios (últimos 10s)
  bool _detectTypingActivity() {
    if (_messages.isEmpty) return false;
    final now = DateTime.now();
    // Buscar mensajes de OTROS usuarios en los últimos 10 segundos
    final recentOthers = _messages.where((m) =>
        m.userCode != widget.userCode &&
        now.difference(m.createdAt).inSeconds < 10);
    return recentOthers.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final inputBgColor = isDark ? AppTheme.darkSurface : Colors.grey[100]!;
    final inputTextColor = isDark ? Colors.white : Colors.black87;
    final inputHintColor = isDark ? Colors.grey[500]! : Colors.grey[400]!;
    final inputBarBg = isDark ? AppTheme.darkCard : Colors.white;

    // Verificar typing cada 2 segundos
    _someoneIsTyping = _detectTypingActivity();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.sectionChat,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                color: Colors.greenAccent,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            const Text('Chat Vecinal'),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${_messages.length} msgs',
              style: const TextStyle(fontSize: 12, color: Colors.white),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Banner de anonimato
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: AppTheme.primaryGreen.withValues(alpha: 0.05),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 14, color: Colors.grey[500]),
                const SizedBox(width: 8),
                Text(
                  'Todos los mensajes son anónimos. Usa tu código asignado.',
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? _buildEmptyChat(isDark)
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(12),
                        itemCount: _messages.length + (_someoneIsTyping ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == _messages.length && _someoneIsTyping) {
                            return _buildTypingBanner(isDark);
                          }
                          final msg = _messages[index];
                          final isMine = msg.userCode == widget.userCode;
                          return _ChatBubble(
                            message: msg,
                            isMine: isMine,
                          );
                        },
                      ),
          ),
          // Indicador "Alguien está escribiendo..."
          if (_someoneIsTyping)
            _buildTypingBanner(isDark),
          // Input bar con dark mode
          _buildInputBar(isDark, inputBgColor, inputTextColor, inputHintColor, inputBarBg),
        ],
      ),
    );
  }

  Widget _buildInputBar(
      bool isDark, Color inputBgColor, Color inputTextColor, Color inputHintColor, Color inputBarBg) {
    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: BoxDecoration(
        color: inputBarBg,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              decoration: InputDecoration(
                hintText: 'Escribe un mensaje...',
                hintStyle: TextStyle(color: inputHintColor),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: inputBgColor,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
              style: TextStyle(color: inputTextColor),
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendMessage(),
              maxLines: 3,
              minLines: 1,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            decoration: const BoxDecoration(
              color: AppTheme.primaryGreen,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              onPressed: _isSending ? null : _sendMessage,
              icon: const Icon(Icons.send_rounded, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypingBanner(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: isDark
          ? AppTheme.darkCard.withValues(alpha: 0.8)
          : AppTheme.primaryGreen.withValues(alpha: 0.05),
      child: Row(
        children: [
          _TypingDots(),
          const SizedBox(width: 8),
          Text(
            'Alguien está escribiendo...',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyChat(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 64,
            color: isDark ? Colors.grey[700] : Colors.grey[300],
          ),
          const SizedBox(height: 16),
          Text(
            'Sé el primero en escribir',
            style: TextStyle(
              fontSize: 16,
              color: isDark ? Colors.grey[500] : Colors.grey[500],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Saluda a tus vecinos de Collique',
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.grey[600] : Colors.grey[400],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// TYPING INDICATOR — Puntos animados
// ============================================================

class _TypingDots extends StatefulWidget {
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            final delay = index * 0.2;
            final value = ((_controller.value - delay) % 1.0).clamp(0.0, 1.0);
            final scale = 0.5 + (0.5 * (1 - (value * 2 - 1).abs()));
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Transform.scale(
                scale: scale,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: Colors.grey[400],
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

// ============================================================
// BURBUJA DE MENSAJE
// ============================================================

class _ChatBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMine;

  const _ChatBubble({required this.message, required this.isMine});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        child: Column(
          crossAxisAlignment:
              isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(
                left: isMine ? 0 : 12,
                right: isMine ? 12 : 0,
                bottom: 2,
              ),
              child: Text(
                message.userCode,
                style: TextStyle(
                  fontSize: 10,
                  color: isMine
                      ? AppTheme.primaryGreen.withValues(alpha: 0.7)
                      : Colors.grey[500],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isMine ? AppTheme.primaryGreen : Colors.grey[100],
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isMine ? 18 : 4),
                  bottomRight: Radius.circular(isMine ? 4 : 18),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.content,
                    style: TextStyle(
                      fontSize: 14,
                      color: isMine ? Colors.white : Colors.black87,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    timeago.format(message.createdAt, locale: 'es'),
                    style: TextStyle(
                      fontSize: 10,
                      color: isMine
                          ? Colors.white.withValues(alpha: 0.6)
                          : Colors.grey[500],
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
}
