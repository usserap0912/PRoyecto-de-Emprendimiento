import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:safezone/services/supabase_service.dart';
import 'package:safezone/services/zonebot_service.dart';

// ============================================================
// PAYMENT SERVICE
// ============================================================
// Maneja la suscripcion premium usando:
//   - Stripe Checkout para el pago
//   - Supabase Edge Function para crear sesiones y verificar estado
//   - Supabase Database para persistir el estado premium
// ============================================================

/// Resultado de una operacion de compra premium.
enum PaymentResult {
  /// Compra exitosa (modo demo o pago confirmado)
  success,

  /// Redirigido a Stripe Checkout (pendiente de confirmacion)
  redirected,

  /// Error en el proceso de pago
  failed,
}

/// Servicio de pagos para SafeZone Premium.
class PaymentService {
  static const String _functionBaseUrl =
      'https://kpkdgejbjgmrbyemubmx.supabase.co/functions/v1/stripe-premium';

  static bool _demoMode = true;

  static void setDemoMode(bool value) {
    _demoMode = value;
    debugPrint('PaymentService: Demo mode ${value ? "activado" : "desactivado"}');
  }

  static bool get isDemoMode => _demoMode;

  static void initialize({
    String publishableKey = 'pk_test_placeholder',
  }) {
    Stripe.publishableKey = publishableKey;
    debugPrint('PaymentService: Stripe inicializado');
  }

  /// Inicia el flujo de compra premium.
  Future<PaymentResult> purchasePremium({
    required String userCode,
    required int zone,
  }) async {
    // Modo demo: activar premium localmente sin pago real
    if (_demoMode) {
      debugPrint('PaymentService: Modo demo - activando premium sin pago');
      ZoneBotService.setPremium(true);
      return PaymentResult.success;
    }

    // Modo real: Stripe Checkout
    try {
      final response = await http.post(
        Uri.parse('$_functionBaseUrl/checkout'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userCode': userCode,
          'zone': zone,
        }),
      );

      if (response.statusCode != 200) {
        debugPrint('PaymentService: Error creando checkout: ${response.body}');
        return PaymentResult.failed;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final checkoutUrl = data['url'] as String?;

      if (checkoutUrl == null) {
        debugPrint('PaymentService: No se recibio URL de checkout');
        return PaymentResult.failed;
      }

      // Abrir Stripe Checkout en el navegador
      debugPrint('PaymentService: Abriendo checkout: $checkoutUrl');
      final uri = Uri.parse(checkoutUrl);
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return PaymentResult.redirected;
      } catch (e) {
        debugPrint('PaymentService: Error abriendo checkout: $e');
        return PaymentResult.failed;
      }
    } catch (e) {
      debugPrint('PaymentService: Error en compra premium: $e');
      return PaymentResult.failed;
    }
  }

  /// Verifica si un usuario tiene premium activo.
  Future<bool> checkPremiumStatus({required String userCode}) async {
    if (_demoMode) {
      return ZoneBotService.isPremium;
    }

    try {
      final response = await http.get(
        Uri.parse('$_functionBaseUrl/status?user_code=$userCode'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data['is_premium'] as bool? ?? false;
      }
    } catch (e) {
      debugPrint('PaymentService: Error verificando premium: $e');
    }

    return ZoneBotService.isPremium;
  }

  /// Sincroniza el estado premium desde Supabase a ZoneBotService.
  static Future<void> syncPremiumStatus({required String userCode}) async {
    if (_demoMode) return;

    try {
      final profile = await SupabaseService().getProfileByCode(userCode);
      if (profile != null) {
        final isPremium = profile['is_premium'] as bool? ?? false;
        ZoneBotService.setPremium(isPremium);
        debugPrint('PaymentService: Premium sincronizado desde Supabase: $isPremium');
      }
    } catch (e) {
      debugPrint('PaymentService: Error sincronizando premium: $e');
    }
  }
}
