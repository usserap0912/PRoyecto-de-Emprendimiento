import 'dart:async';
import 'package:flutter/material.dart';
import 'package:safezone/theme/app_theme.dart';
import 'package:safezone/models/zonebot_message.dart';
import 'package:safezone/services/zonebot_service.dart';
import 'package:safezone/services/payment_service.dart';
import 'package:safezone/services/sound_service.dart';
import 'package:safezone/widgets/zonebot_avatar.dart';
import 'package:timeago/timeago.dart' as timeago;

class ZoneBotScreen extends StatefulWidget {
  final String userCode;
  final int zone;

  const ZoneBotScreen({
    super.key,
    required this.userCode,
    required this.zone,
  });

  @override
  State<ZoneBotScreen> createState() => _ZoneBotScreenState();
}

class _ZoneBotScreenState extends State<ZoneBotScreen> {
  final ZoneBotService _zoneBotService = ZoneBotService();
  final PaymentService _paymentService = PaymentService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ZoneBotMessage> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  bool _isPurchasingPremium = false;

  // ============================================================
  // ESTADO DE ANIMACIÓN DE ZONEBOT
  // ============================================================
  // Cambia según el flujo del chat:
  //   'idle'     → Estado de respiración/espera por defecto
  //   'thinking' → Mientras la API está procesando o cargando
  //   'happy'    → Cuando el bot responda con éxito o use emojis de celebración
  // ============================================================
  String _botAnimationState = 'idle';

  @override
  void initState() {
    super.initState();
    SoundService().initialize();
    _loadHistoryAndInitialize();
  }

  /// Carga el historial guardado o inicia el chat desde cero.
  Future<void> _loadHistoryAndInitialize() async {
    setState(() => _botAnimationState = 'thinking');

    try {
      // Intentar cargar historial guardado
      final savedHistory = await ZoneBotService.loadChatHistory();

      if (!mounted) return;

      if (savedHistory.isNotEmpty) {
        // Hay historial previo → restaurarlo
        _messages.addAll(savedHistory);
        setState(() {
          _isLoading = false;
          _botAnimationState = 'idle';
        });
        debugPrint('ZoneBot: Historial restaurado (${savedHistory.length} mensajes)');
      } else {
        // No hay historial → iniciar chat nuevo
        await _startNewChat();
      }

      _scrollToBottom();

      // Sincronizar estado premium desde Supabase
      if (!mounted) return;
      PaymentService.syncPremiumStatus(userCode: widget.userCode);
    } catch (e) {
      if (!mounted) return;
      await _startNewChat();
    }
  }

  /// Inicia un nuevo chat: consejo del día + saludo de ZoneBot.
  Future<void> _startNewChat() async {
    try {
      final dailyTip = await _zoneBotService.getDailyTip();

      if (!mounted) return;

      _messages.addAll([
        ZoneBotMessage.bot(
          id: 'welcome',
          content: '¡Hola, vecino **${widget.userCode}**! 🦸‍♂️\n\n'
              'Soy **ZoneBot**, tu robot guardián de SafeZone en Collique. '
              'Estoy aquí para ayudarte a mantener segura nuestra comunidad.\n\n'
              'Esto es lo que puedo hacer por ti:\n'
              '🛡️ Darte el **Consejo Creativo del Día**\n'
              '🗺️ Guiarte en el uso del **Mapa de Riesgo**\n'
              '🚨 Ayudarte con el **botón S.O.S.**\n'
              '💬 Responder tus dudas sobre la app\n\n'
              '¿En qué te ayudo hoy?',
          botAnimationState: 'happy',
          createdAt: DateTime.now().subtract(const Duration(seconds: 2)),
        ),
        ZoneBotMessage.bot(
          id: 'daily_tip',
          content: '🌟 **CONSEJO DEL DÍA** 🌟\n\n$dailyTip',
          botAnimationState: 'happy',
          createdAt: DateTime.now(),
        ),
      ]);

      setState(() {
        _isLoading = false;
        _botAnimationState = 'idle';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _botAnimationState = 'idle';
      });
    }
  }

  /// Envía un mensaje del usuario y obtiene respuesta de ZoneBot.
  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty || _isSending) return;

    // Verificar créditos de mensaje
    if (!ZoneBotService.consumeMessageToken()) {
      _showPremiumDialog('mensajes');
      return;
    }

    _messageController.clear();

    // Agregar mensaje del usuario
    setState(() {
      _messages.add(ZoneBotMessage.user(
        id: 'user_${DateTime.now().millisecondsSinceEpoch}',
        content: content,
        createdAt: DateTime.now(),
      ));
      _isSending = true;
      _botAnimationState = 'thinking';
      SoundService().playStateSound('thinking');
    });
    _scrollToBottom();

    try {
      // Obtener respuesta de ZoneBot con todo el historial de la conversación
      final response = await _zoneBotService.getResponse(
        content,
        history: _messages,
      );

      if (!mounted) return;

      // Determinar si la respuesta contiene emojis de celebración
      final hasCelebrationEmojis = response.contains('🛡️') ||
          response.contains('🚨') ||
          response.contains('🎉') ||
          response.contains('🏆');

      final newState = hasCelebrationEmojis ? 'happy' : 'idle';
      setState(() {
        _messages.add(ZoneBotMessage.bot(
          id: 'bot_${DateTime.now().millisecondsSinceEpoch}',
          content: response,
          botAnimationState: newState,
          createdAt: DateTime.now(),
        ));
        _isSending = false;
        _botAnimationState = newState;
      });

      // Reproducir sonido solo para estados no-idle
      if (newState != 'idle') {
        SoundService().playStateSound(newState);
      }

      _scrollToBottom();

      // Persistir historial actualizado
      _saveHistory();

      // Volver a idle después de un momento si estábamos en happy
      if (hasCelebrationEmojis) {
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            setState(() => _botAnimationState = 'idle');
          }
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add(ZoneBotMessage.bot(
          id: 'bot_error_${DateTime.now().millisecondsSinceEpoch}',
          content: '¡Ups! 😅 Parece que tuve un problema de conexión. '
              '¿Puedes repetirme eso? ¡No te preocupes, estoy aquí! 🛡️',
          botAnimationState: 'idle',
          createdAt: DateTime.now(),
        ));
        _isSending = false;
        _botAnimationState = 'idle';
      });
      _scrollToBottom();
    }
  }

  /// Guarda el historial actual en SharedPreferences.
  void _saveHistory() {
    ZoneBotService.saveChatHistory(_messages);
  }

  /// Reinicia la conversación (nuevo chat).
  Future<void> _resetChat() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Nueva conversación?'),
        content: const Text(
          'Se borrará todo el historial de esta conversación. '
          'Los mensajes anteriores no se podrán recuperar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.dangerRed),
            child: const Text('Nueva conversación'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    // Verificar créditos de reset
    if (!ZoneBotService.consumeResetToken()) {
      _showPremiumDialog('resets de conversación');
      return;
    }

    setState(() {
      _isLoading = true;
      _messages.clear();
      _botAnimationState = 'thinking';
    });

    // Limpiar historial guardado y contadores
    await ZoneBotService.clearChatHistory();
    ZoneBotService.resetTokenCounters();

    // Iniciar nuevo chat
    await _startNewChat();

    _scrollToBottom();
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

  @override
  void dispose() {
    _saveHistory();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Indicador de estado animado
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: _botAnimationState == 'thinking'
                    ? Colors.orangeAccent
                    : Colors.greenAccent,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: (_botAnimationState == 'thinking'
                            ? Colors.orangeAccent
                            : Colors.greenAccent)
                        .withValues(alpha: 0.6),
                    blurRadius: 6,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            const Text('ZoneBot'),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.greenAccent.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'En línea 🟢',
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.greenAccent,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        actions: [
          // Contador de tokens de mensaje
          Padding(
            padding: const EdgeInsets.only(right: 2),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: ZoneBotService.isPremium
                      ? Colors.amber.withValues(alpha: 0.25)
                      : ZoneBotService.messageTokens <= 3
                          ? Colors.red.withValues(alpha: 0.25)
                          : Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      ZoneBotService.isPremium
                          ? Icons.star
                          : Icons.chat_bubble_outline,
                      size: 12,
                      color: ZoneBotService.isPremium
                          ? Colors.amber
                          : Colors.white,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      ZoneBotService.isPremium
                          ? '∞'
                          : '${ZoneBotService.messageTokens}',
                      style: TextStyle(
                        fontSize: 11,
                        color: ZoneBotService.isPremium
                            ? Colors.amber
                            : Colors.white,
                        fontWeight: ZoneBotService.messageTokens <= 3
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Contador de tokens de reset
          Padding(
            padding: const EdgeInsets.only(right: 2),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: ZoneBotService.isPremium
                      ? Colors.amber.withValues(alpha: 0.25)
                      : ZoneBotService.resetTokens <= 1
                          ? Colors.red.withValues(alpha: 0.25)
                          : Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      ZoneBotService.isPremium
                          ? Icons.star
                          : Icons.refresh,
                      size: 12,
                      color: ZoneBotService.isPremium
                          ? Colors.amber
                          : Colors.white,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      ZoneBotService.isPremium
                          ? '∞'
                          : '${ZoneBotService.resetTokens}',
                      style: TextStyle(
                        fontSize: 11,
                        color: ZoneBotService.isPremium
                            ? Colors.amber
                            : Colors.white,
                        fontWeight: ZoneBotService.resetTokens <= 1
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Botón de reset
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              icon: Icon(
                Icons.delete_outline,
                size: 20,
                color: ZoneBotService.resetTokens <= 0 && !ZoneBotService.isPremium
                    ? Colors.grey
                    : Colors.white,
              ),
              tooltip: 'Nueva conversación',
              onPressed: (_isSending ||
                      (ZoneBotService.resetTokens <= 0 && !ZoneBotService.isPremium))
                  ? null
                  : _resetChat,
              color: Colors.white,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // ============================================================
          // AVATAR ANIMADO DE ZONEBOT
          // ============================================================
          // ZoneBotAvatar usa CustomPainter con animaciones para:
          //   'idle'     → Respiración suave, escudo pulsante
          //   'thinking' → Anillo de carga giratorio
          //   'happy'    → Destellos de celebración
          //
          // Para reemplazar con Rive (.riv), editar:
          //   lib/widgets/zonebot_avatar.dart
          // El .riv debe colocarse en: assets/animations/zonebot.riv
          // ============================================================
          _buildZoneBotHeader(isDark),

          // Área de mensajes
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? _buildEmptyChat()
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final msg = _messages[index];
                          return _ZoneBotBubble(
                            message: msg,
                            userCode: widget.userCode,
                          );
                        },
                      ),
          ),

          // Barra de entrada de texto
          _buildInputBar(isDark),
        ],
      ),
    );
  }

  /// Encabezado con avatar animado de ZoneBot y texto de estado.
  Widget _buildZoneBotHeader(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: isDark
            ? AppTheme.darkCard.withValues(alpha: 0.5)
            : AppTheme.primaryGreen.withValues(alpha: 0.05),
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
            width: 0.5,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Avatar animado de ZoneBot
          ZoneBotAvatar(
            state: _botAnimationState,
            size: _botAnimationState == 'thinking' ? 76 : 70,
          ),
          const SizedBox(height: 8),
          // Nombre
          Text(
            'ZoneBot',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 2),
          // Texto de estado
          Text(
            _botAnimationState == 'thinking'
                ? 'Pensando...'
                : _botAnimationState == 'happy'
                    ? '¡Feliz de ayudarte!'
                    : 'Siempre vigilante',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  /// Restaura compras previas verificando el estado premium en Supabase.
  Future<void> _restorePurchases() async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    scaffoldMessenger.showSnackBar(
      const SnackBar(
        content: Text('🔄 Verificando estado premium...'),
        backgroundColor: Colors.blue,
        duration: Duration(seconds: 2),
      ),
    );

    try {
      // Primero intentar sincronizar desde Supabase
      await PaymentService.syncPremiumStatus(userCode: widget.userCode);

      if (ZoneBotService.isPremium) {
        setState(() {});
        scaffoldMessenger.hideCurrentSnackBar();
        scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text('🎉 ¡Premium restaurado correctamente!'),
            backgroundColor: Colors.green,
          ),
        );
      } else if (!PaymentService.isDemoMode) {
        // Modo real: consultar la Edge Function directamente
        final isPremium = await _paymentService.checkPremiumStatus(
          userCode: widget.userCode,
        );
        if (isPremium) {
          ZoneBotService.setPremium(true);
          setState(() {});
          scaffoldMessenger.hideCurrentSnackBar();
          scaffoldMessenger.showSnackBar(
            const SnackBar(
              content: Text('🎉 ¡Premium restaurado correctamente!'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          scaffoldMessenger.hideCurrentSnackBar();
          scaffoldMessenger.showSnackBar(
            const SnackBar(
              content: Text('No se encontró una suscripción premium activa.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } else {
        scaffoldMessenger.hideCurrentSnackBar();
        scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text('Modo demo: no hay compras que restaurar.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      scaffoldMessenger.hideCurrentSnackBar();
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('❌ Error al restaurar: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Muestra diálogo para invitar a premium cuando se acaban los créditos.
  void _showPremiumDialog(String recurso) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.star, color: Colors.amber),
            const SizedBox(width: 8),
            const Text('¡Sin créditos!'),
          ],
        ),
        content: Text(
          'Te has quedado sin créditos de $recurso. '
          'Activa SafeZone Premium para obtener acceso ilimitado '
          'a todas las funciones de ZoneBot.\n\n'
          '✨ Mensajes ilimitados\n'
          '🔄 Resets ilimitados\n'
          '🛡️ Sin restricciones',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _restorePurchases();
            },
            child: const Text('🔄 Restaurar compras'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.star, size: 18),
            label: const Text('¡Quiero Premium!'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber,
              foregroundColor: Colors.black,
            ),
            onPressed: _isPurchasingPremium
                ? null
                : () async {
                    Navigator.of(ctx).pop();
                    setState(() => _isPurchasingPremium = true);

                    if (PaymentService.isDemoMode) {
                      // Modo demo: activar premium local
                      ZoneBotService.setPremium(true);
                      setState(() => _isPurchasingPremium = false);
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('🎉 ¡Premium activado! (modo demo)'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    } else {
                      // Modo real: Stripe Checkout
                      final result = await _paymentService.purchasePremium(
                        userCode: widget.userCode,
                        zone: widget.zone,
                      );
                      setState(() => _isPurchasingPremium = false);
                      if (!mounted) return;
                      switch (result) {
                        case PaymentResult.success:
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('🎉 ¡Premium activado!'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        case PaymentResult.redirected:
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('🔗 Redirigiendo a Stripe... Vuelve cuando hayas completado el pago.'),
                              backgroundColor: Colors.blue,
                              duration: Duration(seconds: 5),
                            ),
                          );
                        case PaymentResult.failed:
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('❌ Error al procesar el pago. Intenta de nuevo.'),
                              backgroundColor: Colors.red,
                            ),
                          );
                      }
                    }

                    setState(() {});
                  },
          ),
        ],
      ),
    );
  }

  /// Barra inferior de entrada de texto.
  Widget _buildInputBar(bool isDark) {
    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
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
                hintText: 'Escribe a ZoneBot...',
                hintStyle: TextStyle(
                  color: isDark ? Colors.grey[500] : Colors.grey[400],
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: isDark ? AppTheme.darkSurface : Colors.grey[100],
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendMessage(),
              maxLines: 3,
              minLines: 1,
              enabled: !_isSending &&
                  (ZoneBotService.isPremium || ZoneBotService.messageTokens > 0),
            ),
          ),
          const SizedBox(width: 8),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: _isSending
                  ? Colors.grey
                  : AppTheme.primaryGreen,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              onPressed: _isSending ? null : _sendMessage,
              icon: _isSending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.send_rounded, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyChat() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.shield_outlined,
            size: 64,
            color: isDark ? Colors.grey[700] : Colors.grey[300],
          ),
          const SizedBox(height: 16),
          Text(
            'Ningún mensaje aún',
            style: TextStyle(
              fontSize: 16,
              color: isDark ? Colors.grey[500] : Colors.grey[500],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'ZoneBot te está esperando',
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
// BURBUJA DE MENSAJE
// ============================================================

class _ZoneBotBubble extends StatelessWidget {
  final ZoneBotMessage message;
  final String userCode;

  const _ZoneBotBubble({
    required this.message,
    required this.userCode,
  });

  @override
  Widget build(BuildContext context) {
    final isBot = message.isBot;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment:
            isBot ? CrossAxisAlignment.start : CrossAxisAlignment.end,
        children: [
          // Nombre del remitente
          Padding(
            padding: EdgeInsets.only(
              left: isBot ? 4 : 0,
              right: isBot ? 0 : 4,
              bottom: 3,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isBot) ...[
                  const Icon(Icons.shield_rounded,
                      size: 12, color: AppTheme.primaryGreen),
                  const SizedBox(width: 4),
                  Text(
                    'ZoneBot',
                    style: TextStyle(
                      fontSize: 10,
                      color: AppTheme.primaryGreen,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ] else ...[
                  Text(
                    userCode,
                    style: TextStyle(
                      fontSize: 10,
                      color: isDark ? Colors.grey[400] : Colors.grey[500],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.person_outline,
                      size: 12, color: isDark ? Colors.grey[400] : Colors.grey[500]),
                ],
              ],
            ),
          ),
          // Contenido de la burbuja
          Row(
            mainAxisAlignment:
                isBot ? MainAxisAlignment.start : MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Avatar pequeño del bot (solo mensajes del bot)
              if (isBot)
                Container(
                  width: 28,
                  height: 28,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        AppTheme.primaryGreen,
                        AppTheme.brandRedBright,
                      ],
                    ),
                  ),
                  child: const Icon(Icons.shield_rounded,
                      size: 14, color: Colors.white),
                ),
              // Burbuja de texto
              Flexible(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isBot
                        ? (isDark
                            ? AppTheme.darkSurface
                            : AppTheme.primaryGreen.withValues(alpha: 0.08))
                        : AppTheme.primaryGreen,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: Radius.circular(isBot ? 4 : 18),
                      bottomRight: Radius.circular(isBot ? 18 : 4),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        message.content,
                        style: TextStyle(
                          fontSize: 14,
                          color: isBot
                              ? (isDark ? Colors.white : Colors.black87)
                              : Colors.white,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        timeago.format(message.createdAt, locale: 'es'),
                        style: TextStyle(
                          fontSize: 10,
                          color: isBot
                              ? (isDark
                                  ? Colors.grey[500]
                                  : Colors.grey[600])
                              : Colors.white.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
