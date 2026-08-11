import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';
import 'package:safezone/theme/app_theme.dart';
import 'package:safezone/services/zonebot_service.dart';
import 'package:safezone/services/payment_service.dart';
import 'package:safezone/services/sound_service.dart';
import 'package:safezone/services/supabase_service.dart';

// ============================================================
// PREMIUM SCREEN
// ============================================================

class PremiumScreen extends StatefulWidget {
  final String userCode;
  final int zone;
  final VoidCallback? onPremiumChanged;

  const PremiumScreen({
    super.key,
    required this.userCode,
    required this.zone,
    this.onPremiumChanged,
  });

  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen>
    with TickerProviderStateMixin {
  final PaymentService _paymentService = PaymentService();
  bool _isPurchasing = false;
  bool _isRestoring = false;
  bool _isCancelling = false;

  // Animaciones
  late AnimationController _pulseController;
  late AnimationController _staggerController;
  late final List<Animation<double>> _staggerAnimations;

  // Confetti (Lottie)
  late AnimationController _confettiController;
  bool _showConfetti = false;

  // ============================================================
  // BENEFICIOS
  // ============================================================
  static const List<_PremiumBenefit> _benefits = [
    _PremiumBenefit(
      icon: Icons.forum,
      title: 'Tickets ilimitados',
      description: 'Chatea con ZoneBot sin restricciones. ♾️',
      color: Colors.amber,
    ),
    _PremiumBenefit(
      icon: Icons.refresh,
      title: 'Resets ilimitados',
      description: 'Reinicia la conversación cuantas veces quieras.',
      color: Colors.orange,
    ),
    _PremiumBenefit(
      icon: Icons.shield,
      title: 'Insignia exclusiva',
      description: 'Badge Premium en tu perfil. 🏆',
      color: AppTheme.shieldBlue,
    ),
    _PremiumBenefit(
      icon: Icons.notifications_active,
      title: 'Alertas prioritarias',
      description: 'Recibe notificaciones de robos cerca de ti. 🚨',
      color: AppTheme.sosRed,
    ),
    _PremiumBenefit(
      icon: Icons.star,
      title: 'Sin anuncios',
      description: 'Experiencia libre de distracciones.',
      color: Colors.purple,
    ),
    _PremiumBenefit(
      icon: Icons.support_agent,
      title: 'Soporte prioritario',
      description: 'Ayuda rápida cuando más la necesitas.',
      color: Colors.teal,
    ),
  ];

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    _staggerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _staggerAnimations = List.generate(_benefits.length, (index) {
      return Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: _staggerController,
          curve: Interval(
            index * 0.08,
            index * 0.08 + 0.4,
            curve: Curves.easeOutCubic,
          ),
        ),
      );
    });

    // Confetti controller (controla el Lottie)
    _confettiController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000), // 60fr/60fps = 1s nativo
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _staggerController.forward();
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _staggerController.dispose();
    _confettiController.dispose();
    super.dispose();
  }

  /// Lanza la animación de confetti (Lottie real)
  void _triggerConfetti() {
    setState(() => _showConfetti = true);
    _confettiController.forward(from: 0.0);

    // Ocultar confetti automáticamente después de que termine
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _showConfetti = false);
    });
  }

  Future<void> _purchasePremium() async {
    HapticFeedback.mediumImpact();
    setState(() => _isPurchasing = true);

    try {
      if (PaymentService.isDemoMode) {
        await Future.delayed(const Duration(milliseconds: 600));
        ZoneBotService.setPremium(true);
        SoundService().play('happy');

        if (!mounted) return;
        setState(() => _isPurchasing = false);
        widget.onPremiumChanged?.call();
        _triggerConfetti();
        _showPremiumToast(
          '🎉 ¡Premium activado! (modo demo)',
          color: Colors.green,
        );
        _staggerController.reset();
        _staggerController.forward();
        return;
      }

      final result = await _paymentService.purchasePremium(
        userCode: widget.userCode,
        zone: widget.zone,
      );

      if (!mounted) return;
      setState(() => _isPurchasing = false);

      switch (result) {
        case PaymentResult.success:
          widget.onPremiumChanged?.call();
          _triggerConfetti();
          _showPremiumToast(
            '🎉 ¡Premium activado correctamente!',
            color: Colors.green,
          );
          _staggerController.reset();
          _staggerController.forward();
        case PaymentResult.redirected:
          _showPremiumToast(
            '🔗 Abriendo Mercado Pago... Vuelve cuando hayas completado el pago.',
            color: Colors.blue,
            icon: Icons.link,
          );
        case PaymentResult.failed:
          _showPremiumToast(
            '❌ Error al procesar el pago. Intenta de nuevo.',
            color: Colors.red,
            icon: Icons.error_outline,
          );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isPurchasing = false);
      _showPremiumToast('❌ Error: $e', color: Colors.red, icon: Icons.error);
    }
  }

  Future<void> _restorePurchases() async {
    HapticFeedback.lightImpact();
    setState(() => _isRestoring = true);

    try {
      await PaymentService.syncPremiumStatus(userCode: widget.userCode);

      if (!mounted) return;
      setState(() => _isRestoring = false);

      if (ZoneBotService.isPremium) {
        widget.onPremiumChanged?.call();
        _triggerConfetti();
        _showPremiumToast(
          '🎉 ¡Premium restaurado correctamente!',
          color: Colors.green,
        );
        _staggerController.reset();
        _staggerController.forward();
      } else {
        _showPremiumToast(
          'No se encontró una suscripción premium activa.',
          color: Colors.orange,
          icon: Icons.search_off,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isRestoring = false);
      _showPremiumToast(
        '❌ Error al restaurar: $e',
        color: Colors.red,
        icon: Icons.error,
      );
    }
  }

  /// Cancela la suscripción Premium (Mercado Pago)
  Future<void> _cancelSubscription() async {
    HapticFeedback.mediumImpact();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.cancel_outlined, color: Colors.orange),
            SizedBox(width: 8),
            Text('¿Cancelar suscripción?'),
          ],
        ),
        content: const Text(
          'Podrás seguir usando Premium hasta el final del período ya pagado. '
          'Para volver a activarlo, suscríbete nuevamente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Seguir con Premium'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _isCancelling = true);
    final cancelled = await _paymentService.cancelPremiumSubscription(
      userCode: widget.userCode,
    );

    if (!mounted) return;
    setState(() => _isCancelling = false);

    if (cancelled) {
      ZoneBotService.setPremium(false);
      widget.onPremiumChanged?.call();
      _showPremiumToast(
        'Suscripción cancelada. Seguirás Premium hasta fin de período.',
        color: Colors.orange,
        icon: Icons.check_circle_outline,
      );
    } else {
      _showPremiumToast(
        '❌ No se pudo cancelar. Intenta de nuevo o cancela en tu cuenta de Mercado Pago.',
        color: Colors.red,
        icon: Icons.error_outline,
      );
    }
  }

  /// Toast unificado con icono, color y animación
  void _showPremiumToast(
    String message, {
    required Color color,
    IconData? icon,
  }) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        duration: const Duration(seconds: 3),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isPremium = ZoneBotService.isPremium;
    final cardColor = isDark ? AppTheme.darkCard : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final mutedColor = isDark ? Colors.grey[500]! : Colors.grey[600]!;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.sectionPremium,
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.star, color: Colors.amber, size: 22),
            SizedBox(width: 8),
            Text('SafeZone Premium'),
          ],
        ),
      ),
      body: Stack(
        children: [
          // Contenido principal
          SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              children: [
                _buildPremiumHeader(isDark, isPremium),
                const SizedBox(height: 28),

                if (!isPremium)
                  _buildCreditsIndicator(
                      isDark, cardColor, textColor, mutedColor),
                if (!isPremium) const SizedBox(height: 24),

                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    isPremium
                        ? '🌟 Tus beneficios'
                        : '✨ Beneficios al suscribirte',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                ...List.generate(_benefits.length, (index) {
                  return AnimatedBuilder(
                    animation: _staggerAnimations[index],
                    builder: (context, child) {
                      return Opacity(
                        opacity: _staggerAnimations[index].value,
                        child: Transform.translate(
                          offset: Offset(
                              0, 20 * (1 - _staggerAnimations[index].value)),
                          child: child,
                        ),
                      );
                    },
                    child: _BenefitTile(
                      benefit: _benefits[index],
                      isDark: isDark,
                      cardColor: cardColor,
                      textColor: textColor,
                      mutedColor: mutedColor,
                    ),
                  );
                }),

                const SizedBox(height: 28),
                _buildRedeemSection(isDark, cardColor, textColor, mutedColor),
                const SizedBox(height: 24),
                _buildCtaButton(isDark, isPremium),
                const SizedBox(height: 12),
                _buildRestoreButton(isDark, isPremium),
                const SizedBox(height: 24),
                _buildFooter(isDark, mutedColor),
                const SizedBox(height: 32),
              ],
            ),
          ),

          // ============================================================
          // CONFETTI OVERLAY — Lottie Animation real
          // ============================================================
          if (_showConfetti)
            Positioned.fill(
              child: IgnorePointer(
                child: Lottie.asset(
                  'assets/animations/confetti.json',
                  controller: _confettiController,
                  fit: BoxFit.cover,
                  repeat: false,
                  animate: true,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPremiumHeader(bool isDark, bool isPremium) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isPremium
              ? [Colors.amber.shade600, Colors.orange.shade800]
              : isDark
                  ? [AppTheme.darkCard, AppTheme.darkSurface]
                  : [AppTheme.primaryGreen, AppTheme.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: (isPremium ? Colors.amber : AppTheme.primaryGreen)
                .withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              return Transform.scale(
                scale: 1.0 + _pulseController.value * 0.08,
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isPremium ? Icons.star : Icons.star_outline,
                    size: 36,
                    color: isPremium ? Colors.amber : Colors.white,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          Text(
            isPremium ? '🦸 ¡Eres Premium!' : 'SafeZone Premium',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isPremium
                ? 'Disfruta de todos los beneficios ilimitados'
                : 'Acceso ilimitado a ZoneBot y más',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.75),
            ),
          ),
          if (isPremium) ...[
            const SizedBox(height: 12),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle, size: 16, color: Colors.white),
                  SizedBox(width: 6),
                  Text(
                    'Suscripción activa',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCreditsIndicator(
      bool isDark, Color cardColor, Color textColor, Color mutedColor) {
    final msgTokens = ZoneBotService.messageTokens;
    final resetTokens = ZoneBotService.resetTokens;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.battery_alert, size: 18, color: mutedColor),
              const SizedBox(width: 8),
              Text(
                'Tus créditos gratuitos',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _CreditBar(
                  label: 'Mensajes',
                  current: msgTokens,
                  max: ZoneBotService.maxMessageTokens,
                  color: AppTheme.shieldBlue,
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _CreditBar(
                  label: 'Resets',
                  current: resetTokens,
                  max: ZoneBotService.maxResetTokens,
                  color: Colors.orange,
                  isDark: isDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Se recargan cada 24 h • Premium = ♾️ ilimitado',
            style: TextStyle(fontSize: 11, color: mutedColor),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 🔄 CANJE DE PUNTOS VECINALES POR PREMIUM
  // ============================================================

  /// Sección de canje de puntos por Premium
  Widget _buildRedeemSection(
      bool isDark, Color cardColor, Color textColor, Color mutedColor) {
    if (ZoneBotService.isPremium) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primaryGreen.withValues(alpha: 0.08),
            Colors.teal.withValues(alpha: 0.04),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.teal.withValues(alpha: 0.25),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.teal.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.swap_horiz, color: Colors.teal, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '🔄 Canjear puntos por Premium',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                    Text(
                      '50 pts = 1 día Premium',
                      style: TextStyle(fontSize: 12, color: mutedColor),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Opciones de canje
          _buildRedeemOption(isDark, mutedColor, 50, 1, '1 día'),
          const SizedBox(height: 8),
          _buildRedeemOption(isDark, mutedColor, 150, 3, '3 días'),
          const SizedBox(height: 8),
          _buildRedeemOption(isDark, mutedColor, 300, 7, '7 días'),
          const SizedBox(height: 8),
          _buildRedeemOption(isDark, mutedColor, 600, 15, '15 días'),
          const SizedBox(height: 14),
          Text(
            '💡 Los puntos se descuentan automáticamente de tu saldo disponible.',
            style: TextStyle(fontSize: 11, color: mutedColor, fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }

  /// Opción individual de canje
  Widget _buildRedeemOption(
      bool isDark, Color mutedColor, int points, int days, String label) {
    return GestureDetector(
      onTap: () => _confirmRedeem(points, days),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkSurface : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.teal.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.teal.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  '$days',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.teal,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '$days día${days > 1 ? 's' : ''} Premium',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.teal,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$points pts',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Confirma y ejecuta el canje de puntos
  Future<void> _confirmRedeem(int points, int days) async {
    HapticFeedback.lightImpact();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.swap_horiz, color: Colors.teal),
            SizedBox(width: 8),
            Text('¿Canjear puntos?'),
          ],
        ),
        content: Text(
          '¿Estás seguro de canjear $points pts por $days día${days > 1 ? 's' : ''} Premium?\n\n'
          'Una vez canjeados, los puntos se descuentan de tu saldo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('¡Canjear!'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    final supabase = SupabaseService();
    final result = await supabase.redeemVecinoPoints(
      userCode: widget.userCode,
      points: points,
    );

    if (!mounted) return;

    final success = result['success'] as bool? ?? false;
    final message = result['message'] as String? ?? '';

    if (success) {
      SoundService().play('fanfare');
      _triggerConfetti();
      _showPremiumToast(
        '🎉 $message',
        color: Colors.teal,
      );
    } else {
      _showPremiumToast(
        message,
        color: Colors.red,
        icon: Icons.error_outline,
      );
    }
  }

  Widget _buildCtaButton(bool isDark, bool isPremium) {
    if (isPremium) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _isCancelling ? null : _cancelSubscription,
          icon: _isCancelling
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.settings, size: 20),
          label: const Text('Cancelar suscripción'),
          style: OutlinedButton.styleFrom(
            foregroundColor: isDark ? Colors.white : AppTheme.primaryGreen,
            side: BorderSide(
              color: isDark ? Colors.grey.shade600 : AppTheme.primaryGreen,
            ),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _isPurchasing ? null : _purchasePremium,
        icon: _isPurchasing
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.black87),
                ),
              )
            : const Icon(Icons.star, size: 22),
        label: Text(
          _isPurchasing ? 'Procesando...' : 'Suscribirme ahora',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.amber.shade600,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 4,
        ),
      ),
    );
  }

  Widget _buildRestoreButton(bool isDark, bool isPremium) {
    return SizedBox(
      width: double.infinity,
      child: TextButton.icon(
        onPressed: _isRestoring ? null : _restorePurchases,
        icon: _isRestoring
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.restore, size: 18),
        label: Text(_isRestoring ? 'Verificando...' : '🔄 Restaurar compras'),
        style: TextButton.styleFrom(
          foregroundColor: isDark ? Colors.grey[400] : Colors.grey[600],
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  Widget _buildFooter(bool isDark, Color mutedColor) {
    return Column(
      children: [
        Text(
          'Pago único mensual. Cancela cuando quieras.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: mutedColor),
        ),
        const SizedBox(height: 4),
        TextButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => _TermsScreen(),
              ),
            );
          },
          child: const Text(
            'Términos y condiciones',
            style: TextStyle(
              fontSize: 12,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================
// BENEFIT TILE
// ============================================================

class _BenefitTile extends StatelessWidget {
  final _PremiumBenefit benefit;
  final bool isDark;
  final Color cardColor;
  final Color textColor;
  final Color mutedColor;

  const _BenefitTile({
    required this.benefit,
    required this.isDark,
    required this.cardColor,
    required this.textColor,
    required this.mutedColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: benefit.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(benefit.icon, color: benefit.color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  benefit.title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  benefit.description,
                  style: TextStyle(fontSize: 12, color: mutedColor),
                ),
              ],
            ),
          ),
          if (ZoneBotService.isPremium)
            Icon(Icons.check_circle, color: Colors.green, size: 20),
        ],
      ),
    );
  }
}

// ============================================================
// CREDIT BAR
// ============================================================

class _CreditBar extends StatelessWidget {
  final String label;
  final int current;
  final int max;
  final Color color;
  final bool isDark;

  const _CreditBar({
    required this.label,
    required this.current,
    required this.max,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = (current / max).clamp(0.0, 1.0);
    final isLow = current <= 2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
            Text(
              '$current/$max',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isLow
                    ? Colors.red
                    : (isDark ? Colors.white : Colors.black87),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: ratio,
            backgroundColor:
                isDark ? Colors.grey.shade800 : Colors.grey.shade200,
            valueColor:
                AlwaysStoppedAnimation<Color>(isLow ? Colors.red : color),
            minHeight: 6,
          ),
        ),
      ],
    );
  }
}

// ============================================================
// MODELO BENEFICIO
// ============================================================

class _PremiumBenefit {
  final IconData icon;
  final String title;
  final String description;
  final Color color;

  const _PremiumBenefit({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
  });
}

// ============================================================
// TÉRMINOS Y CONDICIONES (inline screen)
// ============================================================

class _TermsScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.description_outlined, size: 20),
            SizedBox(width: 8),
            Text('Términos y condiciones'),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _TermsSection(
              icon: Icons.info_outline,
              title: 'Información general',
              content:
                  'SafeZone Premium es un servicio de suscripción mensual '
                  'que otorga acceso ilimitado a todas las funciones de ZoneBot '
                  'y beneficios exclusivos dentro de la aplicación SafeZone.',
              isDark: isDark,
            ),
            _TermsSection(
              icon: Icons.payment,
              title: 'Suscripción y pagos',
              content:
                  'El pago se realiza de forma mensual a través de Mercado Pago. '
                  'Puedes cancelar tu suscripción en cualquier momento. '
                  'Al cancelar, seguirás teniendo acceso a Premium hasta el '
                  'final del período de facturación actual.',
              isDark: isDark,
            ),
            _TermsSection(
              icon: Icons.replay,
              title: 'Cancelaciones y reembolsos',
              content:
                  'Puedes cancelar tu suscripción en cualquier momento desde '
                  'la configuración de tu cuenta. No se ofrecen reembolsos '
                  'parciales por días no utilizados del período de facturación.',
              isDark: isDark,
            ),
            _TermsSection(
              icon: Icons.restore,
              title: 'Restauración de compras',
              content:
                  'Si desinstalas la app o cambias de dispositivo, puedes '
                  'restaurar tu suscripción Premium desde la pantalla de '
                  'suscripción usando el botón "Restaurar compras".',
              isDark: isDark,
            ),
            _TermsSection(
              icon: Icons.privacy_tip_outlined,
              title: 'Privacidad',
              content:
                  'Tus datos de pago son procesados de forma segura por Mercado Pago. '
                  'SafeZone no almacena información de tarjetas de crédito. '
                  'Tu identidad permanece anónima incluso como usuario Premium.',
              isDark: isDark,
            ),
            _TermsSection(
              icon: Icons.gavel,
              title: 'Responsabilidad',
              content:
                  'SafeZone es una herramienta de apoyo a la seguridad vecinal '
                  'y no reemplaza a las autoridades locales. En caso de '
                  'emergencia, contacta siempre a la policía o serenazgo.',
              isDark: isDark,
            ),
            _TermsSection(
              icon: Icons.mail_outline,
              title: 'Contacto',
              content:
                  'Para consultas sobre tu suscripción, escribe a '
                  'soporte@safezone.app. Te responderemos en un máximo de '
                  '24 horas hábiles.',
              isDark: isDark,
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                'Última actualización: Julio 2026',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.grey[600] : Colors.grey[400],
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _TermsSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final String content;
  final bool isDark;

  const _TermsSection({
    required this.icon,
    required this.title,
    required this.content,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppTheme.primaryGreen.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child:
                    Icon(icon, size: 18, color: AppTheme.primaryGreen),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            content,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.grey[400] : Colors.grey[700],
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
